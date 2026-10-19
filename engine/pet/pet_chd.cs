// license:BSD-3-Clause
// copyright-holders:Aaron Giles (MAME's chd.cpp, chdcodec.cpp, cdrom.cpp, which this file ports;
// the full notice is in D-Screen's THIRD-PARTY-NOTICES.txt). The LZMA decoder follows Igor
// Pavlov's LzmaSpec.cpp (public domain).
//
// CHD disc images for Dw1Disc (docs/shareable_pet_plan.md step 1), compiled into the pet's helper
// with pet_helper.cs and run as "pet_helper.exe chd <image> [pid]". A port of MAME's chd.cpp
// (v5 header, the Huffman-coded hunk map), chdcodec.cpp (the CD codecs cdlz, cdzl and cdfl) and
// cdrom.cpp (sync and ECC rebuilt for sectors the compressor stripped). Only the hunks a read
// touches are decoded; each is checked against the map's CRC-16.
// Over its pipes, every reply is a frame: u32 status (0 = ok, 1 = error), u32 length, the bytes.
//   on start                 "frames=N type=MODE2_RAW pregap=P pgtype=V... codecs=cdlz,cdzl,cdfl"
//   "r <lba> <count>"        count sectors of track 1 from lba, as a .bin stores them (2352 bytes
//                            raw, 2048 or 2336 for cooked tracks), cut at the track's end
//   "sha1"                   decodes every hunk: the SHA-1 of the whole image, "<computed> <header's>"
// It exits when stdin closes or the given process ends.
using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Threading;
using System.Collections.Generic;

static class ChdServer {
	static Stream outp;

	static void Reply(int status, byte[] b) {
		byte[] head = new byte[8];
		BitConverter.GetBytes(status).CopyTo(head, 0);
		BitConverter.GetBytes(b.Length).CopyTo(head, 4);
		try { outp.Write(head, 0, 8); outp.Write(b, 0, b.Length); outp.Flush(); }
		catch { Environment.Exit(0); }
	}

	static void Reply(int status, string s) { Reply(status, Encoding.UTF8.GetBytes(s)); }

	static void Watch(object pid) {
		for (;;) {
			try {
				using (System.Diagnostics.Process p = System.Diagnostics.Process.GetProcessById((int)pid))
					if (p.HasExited) Environment.Exit(0);
			} catch { Environment.Exit(0); }
			Thread.Sleep(1000);
		}
	}

	public static void Run(string[] args) {
		outp = Console.OpenStandardOutput();
		if (args.Length > 2) {
			Thread t = new Thread(Watch);
			t.IsBackground = true;
			t.Start(int.Parse(args[2]));
		}
		Chd chd;
		try { chd = new Chd(args[1]); }
		catch (Exception e) { Reply(1, e.Message); return; }
		Reply(0, chd.Info());
		StreamReader inp = new StreamReader(Console.OpenStandardInput(), Encoding.ASCII);
		string line;
		while ((line = inp.ReadLine()) != null) {
			string[] a = line.Trim().Split(' ');
			try {
				if (a.Length == 3 && a[0] == "r") Reply(0, chd.ReadSectors(long.Parse(a[1]), int.Parse(a[2])));
				else if (a[0] == "sha1") Reply(0, chd.Sha1());
				else Reply(1, "unknown command");
			} catch (Exception e) { Reply(1, e.Message); }
		}
	}
}

sealed class Chd {
	const int FRAME = 2448, SECTOR = 2352, SUB = 96;
	// map entry types (chd.cpp)
	const byte TYPE_ZERO = 255;      // an uncompressed CHD's map entry 0: a hunk of zeros
	const byte TYPE_NONE = 4, TYPE_SELF = 5, TYPE_PARENT = 6, RLE_SMALL = 7, RLE_LARGE = 8,
		SELF_0 = 9, SELF_1 = 10, PARENT_SELF = 11, PARENT_0 = 12, PARENT_1 = 13;
	const uint CDLZ = 0x63646c7a, CDZL = 0x63647a6c, CDFL = 0x6364666c;

	FileStream f;
	public long Logical;
	public int HunkBytes, UnitBytes, HunkCount;
	uint[] codecs = new uint[4];
	byte[] rawSha1 = new byte[20];
	byte[] mtype; long[] moffset; uint[] mlength; ushort[] mcrc;
	// track 1
	public long Frames, Start;
	public string Type = "", PgType = "";
	public int Pregap, DataSize;
	// a few decoded hunks, newest last
	List<int> cacheIds = new List<int>();
	List<byte[]> cacheData = new List<byte[]>();

	static long BE(byte[] b, int o, int n) {
		long v = 0;
		for (int i = 0; i < n; i++) v = (v << 8) | b[o + i];
		return v;
	}

	byte[] ReadAt(long pos, int n) {
		byte[] b = new byte[n];
		f.Seek(pos, SeekOrigin.Begin);
		int got = 0;
		while (got < n) {
			int k = f.Read(b, got, n - got);
			if (k <= 0) throw new Exception("chd: truncated file");
			got += k;
		}
		return b;
	}

	public Chd(string path) {
		f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
		if (f.Length < 124) throw new Exception("chd: not a CHD file");
		byte[] h = ReadAt(0, 124);
		if (Encoding.ASCII.GetString(h, 0, 8) != "MComprHD") throw new Exception("chd: not a CHD file");
		int version = (int)BE(h, 12, 4);
		// v3/v4 (chdman before 0.146, 2012) aren't read (CHD-3, the user's call): PS1 CHDs are v5 in
		// practice, and the message says how to convert one
		if (version < 5) throw new Exception("chd: this CHD is too old (version " + version + "). Convert it with \"chdman copy -i old.chd -o new.chd\", or use the .bin/.cue");
		if (version != 5) throw new Exception("chd: version " + version + " isn't read (only v5)");
		for (int i = 0; i < 4; i++) codecs[i] = (uint)BE(h, 16 + i * 4, 4);
		Logical = BE(h, 32, 8);
		long mapOffset = BE(h, 40, 8);
		long metaOffset = BE(h, 48, 8);
		HunkBytes = (int)BE(h, 56, 4);
		UnitBytes = (int)BE(h, 60, 4);
		Array.Copy(h, 64, rawSha1, 0, 20);
		if (BE(h, 104, 8) != 0 || BE(h, 112, 8) != 0 || BE(h, 120, 4) != 0) throw new Exception("chd: needs a parent CHD");
		if (UnitBytes != FRAME || HunkBytes % FRAME != 0) throw new Exception("chd: not a CD image");
		for (int i = 0; i < 4; i++)                       // say so at open, not at the first read (CHD-2)
			if (codecs[i] != 0 && codecs[i] != CDLZ && codecs[i] != CDZL && codecs[i] != CDFL)
				throw new Exception("chd: codec " + Tag(codecs[i]) + " isn't read (only cdlz, cdzl and cdfl)");
		HunkCount = (int)((Logical + HunkBytes - 1) / HunkBytes);
		ReadTracks(metaOffset);
		ReadMap(mapOffset);
	}

	static string Tag(uint c) {
		return Encoding.ASCII.GetString(new byte[] { (byte)(c >> 24), (byte)(c >> 16), (byte)(c >> 8), (byte)c });
	}

	public string Info() {
		StringBuilder c = new StringBuilder();
		for (int i = 0; i < 4; i++) {
			if (codecs[i] == 0) continue;
			if (c.Length > 0) c.Append(',');
			c.Append(Tag(codecs[i]));
		}
		return "frames=" + Frames + " type=" + Type + " pregap=" + Pregap + " pgtype=" + PgType + " codecs=" + c;
	}

	// Track 1 from the CHT2 / CHTR metadata: where its sectors start and how big they are.
	void ReadTracks(long o) {
		string track = null;
		for (int guard = 0; o != 0 && guard < 1000; guard++) {
			byte[] m = ReadAt(o, 16);
			string tag = Encoding.ASCII.GetString(m, 0, 4);
			int len = (int)BE(m, 5, 3);
			long next = BE(m, 8, 8);
			if (tag == "CHT2" || tag == "CHTR") {
				string s = Encoding.ASCII.GetString(ReadAt(o + 16, len)).TrimEnd('\0');
				if (s.StartsWith("TRACK:1 ")) track = s;
			} else if (tag == "CHCD" || tag == "CHGT" || tag == "CHGD") {
				throw new Exception("chd: " + tag + " track metadata isn't read");
			}
			o = next;
		}
		if (track == null) throw new Exception("chd: no track metadata");
		Dictionary<string, string> kv = new Dictionary<string, string>();
		foreach (string part in track.Split(' ')) {
			int c = part.IndexOf(':');
			if (c > 0) kv[part.Substring(0, c)] = part.Substring(c + 1);
		}
		Type = kv.ContainsKey("TYPE") ? kv["TYPE"] : "";
		Frames = long.Parse(kv["FRAMES"]);
		Pregap = kv.ContainsKey("PREGAP") ? int.Parse(kv["PREGAP"]) : 0;
		PgType = kv.ContainsKey("PGTYPE") ? kv["PGTYPE"] : "MODE1";
		switch (Type) {
			case "MODE1_RAW": case "MODE2_RAW": DataSize = 2352; break;
			case "MODE1": case "MODE2_FORM1": DataSize = 2048; break;
			case "MODE2": case "MODE2_FORM_MIX": DataSize = 2336; break;
			default: throw new Exception("chd: track 1 is " + Type + ", not a data track");
		}
		// a pregap stored in the image ("V" types) comes before LBA 0 (chdman, cdrom.cpp)
		Start = PgType.StartsWith("V") ? Pregap : 0;
		Frames -= Start;
	}

	// ---------------------------------------------------------------- the hunk map
	void ReadMap(long mapOffset) {
		mtype = new byte[HunkCount];
		moffset = new long[HunkCount];
		mlength = new uint[HunkCount];
		mcrc = new ushort[HunkCount];
		if (codecs[0] == 0) {                // uncompressed (chdman -c none): u32 hunk numbers, no CRCs
			byte[] m = ReadAt(mapOffset, HunkCount * 4);
			for (int n = 0; n < HunkCount; n++) {
				long e = BE(m, n * 4, 4);
				mtype[n] = e == 0 ? TYPE_ZERO : TYPE_NONE;
				moffset[n] = e * HunkBytes;
			}
			return;
		}
		byte[] mh = ReadAt(mapOffset, 16);
		int mapBytes = (int)BE(mh, 0, 4);
		long first = BE(mh, 4, 6);
		ushort mapCrc = (ushort)BE(mh, 10, 2);
		int lengthBits = mh[12], selfBits = mh[13], parentBits = mh[14];
		Bits bits = new Bits(ReadAt(mapOffset + 16, mapBytes));
		Huffman huff = new Huffman(16, 8);
		huff.ImportTreeRle(bits);
		byte last = 0;
		int rep = 0;
		for (int n = 0; n < HunkCount; n++) {
			if (rep > 0) { mtype[n] = last; rep--; continue; }
			int v = huff.Decode(bits);
			if (v == RLE_SMALL) { mtype[n] = last; rep = 2 + huff.Decode(bits); }
			else if (v == RLE_LARGE) { mtype[n] = last; rep = 2 + 16 + (huff.Decode(bits) << 4); rep += huff.Decode(bits); }
			else mtype[n] = last = (byte)v;
		}
		long cur = first;
		long lastSelf = 0, lastParent = 0;
		byte[] raw = new byte[HunkCount * 12];
		for (int n = 0; n < HunkCount; n++) {
			long offset = cur;
			uint length = 0;
			ushort crc = 0;
			switch (mtype[n]) {
				case 0: case 1: case 2: case 3:
					length = bits.Read(lengthBits);
					cur += length;
					crc = (ushort)bits.Read(16);
					break;
				case TYPE_NONE:
					length = (uint)HunkBytes;
					cur += length;
					crc = (ushort)bits.Read(16);
					break;
				case TYPE_SELF:
					lastSelf = offset = bits.Read(selfBits);
					break;
				case TYPE_PARENT:
					lastParent = offset = bits.Read(parentBits);
					break;
				case SELF_1: case SELF_0:
					if (mtype[n] == SELF_1) lastSelf++;
					mtype[n] = TYPE_SELF;
					offset = lastSelf;
					break;
				case PARENT_SELF:
					mtype[n] = TYPE_PARENT;
					lastParent = offset = (long)n * HunkBytes / UnitBytes;
					break;
				case PARENT_1: case PARENT_0:
					if (mtype[n] == PARENT_1) lastParent += HunkBytes / UnitBytes;
					mtype[n] = TYPE_PARENT;
					offset = lastParent;
					break;
				default:
					throw new Exception("chd: bad map entry " + mtype[n]);
			}
			moffset[n] = offset;
			mlength[n] = length;
			mcrc[n] = crc;
			int r = n * 12;
			raw[r] = mtype[n];
			raw[r + 1] = (byte)(length >> 16); raw[r + 2] = (byte)(length >> 8); raw[r + 3] = (byte)length;
			for (int i = 0; i < 6; i++) raw[r + 4 + i] = (byte)(offset >> (40 - 8 * i));
			raw[r + 10] = (byte)(crc >> 8); raw[r + 11] = (byte)crc;
		}
		if (Crc16(raw, 0, raw.Length) != mapCrc) throw new Exception("chd: the hunk map fails its CRC");
	}

	// ---------------------------------------------------------------- hunks
	byte[] Hunk(int n) { return Hunk(n, 0); }

	byte[] Hunk(int n, int depth) {
		int ci = cacheIds.IndexOf(n);
		if (ci >= 0) return cacheData[ci];
		if (n < 0 || n >= HunkCount || depth > 8) throw new Exception("chd: bad hunk " + n);
		byte[] d;
		switch (mtype[n]) {
			case TYPE_SELF:
				return Hunk((int)moffset[n], depth + 1);
			case TYPE_PARENT:
				throw new Exception("chd: needs a parent CHD");
			case TYPE_NONE:
				d = ReadAt(moffset[n], HunkBytes);
				break;
			case TYPE_ZERO:
				d = new byte[HunkBytes];
				break;
			default:
				d = new byte[HunkBytes];
				byte[] src = ReadAt(moffset[n], (int)mlength[n]);
				uint codec = codecs[mtype[n]];
				if (codec == CDLZ || codec == CDZL) DecodeCd(src, d, codec == CDLZ);
				else if (codec == CDFL) DecodeCdFlac(src, d);
				else throw new Exception("chd: codec " + Tag(codec) + " isn't read (hunk " + n + ")");
				break;
		}
		if (codecs[0] != 0 && Crc16(d, 0, d.Length) != mcrc[n]) throw new Exception("chd: hunk " + n + " fails its CRC");
		cacheIds.Add(n);
		cacheData.Add(d);
		if (cacheIds.Count > 16) { cacheIds.RemoveAt(0); cacheData.RemoveAt(0); }
		return d;
	}

	// cdlz / cdzl (chd_cd_decompressor): the ECC flags, the base length, the sector data (LZMA or
	// deflate), the subcode (deflate), then sync and ECC rebuilt where the flags say so.
	void DecodeCd(byte[] src, byte[] dest, bool lzma) {
		int frames = dest.Length / FRAME;
		int lenBytes = dest.Length < 65536 ? 2 : 3;
		int eccBytes = (frames + 7) / 8;
		int head = eccBytes + lenBytes;
		int baseLen = (int)BE(src, eccBytes, lenBytes);
		byte[] data = new byte[frames * SECTOR];
		if (lzma) Lzma.Decode(src, head, baseLen, data);
		else Inflate(src, head, baseLen, data);
		byte[] sub = new byte[frames * SUB];
		Inflate(src, head + baseLen, src.Length - head - baseLen, sub);
		for (int i = 0; i < frames; i++) {
			Array.Copy(data, i * SECTOR, dest, i * FRAME, SECTOR);
			Array.Copy(sub, i * SUB, dest, i * FRAME + SECTOR, SUB);
			if ((src[i / 8] & (1 << (i % 8))) != 0) {
				int s = i * FRAME;
				dest[s] = 0; dest[s + 11] = 0;
				for (int k = 1; k < 11; k++) dest[s + k] = 0xFF;
				Ecc.Generate(dest, s);
			}
		}
	}

	// cdfl (chd_cd_flac_decompressor): 16-bit stereo FLAC frames, samples big-endian, then the
	// subcode (deflate) from where the last frame ends.
	void DecodeCdFlac(byte[] src, byte[] dest) {
		int frames = dest.Length / FRAME;
		byte[] data = new byte[frames * SECTOR];
		int end = Flac.Decode(src, data);
		byte[] sub = new byte[frames * SUB];
		Inflate(src, end, src.Length - end, sub);
		for (int i = 0; i < frames; i++) {
			Array.Copy(data, i * SECTOR, dest, i * FRAME, SECTOR);
			Array.Copy(sub, i * SUB, dest, i * FRAME + SECTOR, SUB);
		}
	}

	// MAME's zlib codec is raw deflate (inflateInit2 with -MAX_WBITS), which DeflateStream reads.
	static void Inflate(byte[] src, int o, int n, byte[] dest) {
		using (DeflateStream z = new DeflateStream(new MemoryStream(src, o, n), CompressionMode.Decompress)) {
			int got = 0;
			while (got < dest.Length) {
				int k = z.Read(dest, got, dest.Length - got);
				if (k <= 0) throw new Exception("chd: deflate data ends early");
				got += k;
			}
		}
	}

	// ---------------------------------------------------------------- sectors
	public byte[] ReadSectors(long lba, int count) {
		if (lba < 0 || count < 0) throw new Exception("chd: bad read");
		long n = Math.Max(0, Math.Min(count, Frames - lba));
		byte[] o = new byte[n * DataSize];
		int per = HunkBytes / FRAME;
		for (long i = 0; i < n; i++) {
			long fr = Start + lba + i;
			byte[] h = Hunk((int)(fr / per));
			Array.Copy(h, (int)(fr % per) * FRAME, o, i * DataSize, DataSize);
		}
		return o;
	}

	public string Sha1() {
		using (System.Security.Cryptography.SHA1 sha = System.Security.Cryptography.SHA1.Create()) {
			for (int n = 0; n < HunkCount; n++) {
				byte[] h = Hunk(n);
				int len = (int)Math.Min(HunkBytes, Logical - (long)n * HunkBytes);
				sha.TransformBlock(h, 0, len, null, 0);
			}
			sha.TransformFinalBlock(new byte[0], 0, 0);
			return BitConverter.ToString(sha.Hash).Replace("-", "").ToLower() + " " +
				BitConverter.ToString(rawSha1).Replace("-", "").ToLower();
		}
	}

	// CRC-16-CCITT as MAME's crc16_creator (poly 0x1021, start 0xFFFF)
	static ushort[] crcTable;
	public static ushort Crc16(byte[] b, int o, int n) {
		if (crcTable == null) {
			crcTable = new ushort[256];
			for (int i = 0; i < 256; i++) {
				int c = i << 8;
				for (int k = 0; k < 8; k++) c = (c & 0x8000) != 0 ? (c << 1) ^ 0x1021 : c << 1;
				crcTable[i] = (ushort)c;
			}
		}
		ushort crc = 0xFFFF;
		for (int i = 0; i < n; i++) crc = (ushort)((crc << 8) ^ crcTable[(crc >> 8) ^ b[o + i]]);
		return crc;
	}
}

// MSB-first bit reader (MAME's bitstream_in); past the end it reads zeros.
sealed class Bits {
	byte[] b; long pos;
	public Bits(byte[] data) { b = data; }
	public uint Read(int n) {
		uint v = 0;
		for (int i = 0; i < n; i++) {
			long byteAt = pos >> 3;
			int bit = byteAt < b.Length ? (b[byteAt] >> (7 - (int)(pos & 7))) & 1 : 0;
			v = (v << 1) | (uint)bit;
			pos++;
		}
		return v;
	}
	public uint Peek(int n) { long p = pos; uint v = Read(n); pos = p; return v; }
	public void Skip(int n) { pos += n; }
}

// MAME's huffman_decoder: code lengths imported RLE-style, canonical codes longest-first.
sealed class Huffman {
	int numCodes, maxBits;
	int[] lengths;
	int[] lookup;    // (code << 5) | bits, indexed by the next maxBits bits

	public Huffman(int codes, int maxbits) { numCodes = codes; maxBits = maxbits; lengths = new int[codes]; }

	public void ImportTreeRle(Bits bits) {
		int numBits = maxBits >= 16 ? 5 : maxBits >= 8 ? 4 : 3;
		int cur = 0;
		while (cur < numCodes) {
			int nb = (int)bits.Read(numBits);
			if (nb != 1) { lengths[cur++] = nb; continue; }
			nb = (int)bits.Read(numBits);
			if (nb == 1) { lengths[cur++] = nb; continue; }
			int rep = (int)bits.Read(numBits) + 3;
			while (rep-- > 0) {
				if (cur >= numCodes) throw new Exception("chd: bad Huffman tree");
				lengths[cur++] = nb;
			}
		}
		uint[] histo = new uint[33];
		foreach (int l in lengths) {
			if (l > maxBits) throw new Exception("chd: bad Huffman tree");
			histo[l]++;
		}
		uint start = 0;
		for (int len = 32; len > 0; len--) {
			uint next = (start + histo[len]) >> 1;
			if (len != 1 && next * 2 != start + histo[len]) throw new Exception("chd: bad Huffman tree");
			histo[len] = start;
			start = next;
		}
		lookup = new int[1 << maxBits];
		for (int c = 0; c < numCodes; c++) {
			int l = lengths[c];
			if (l == 0) continue;
			int code = (int)histo[l]++;
			int shift = maxBits - l;
			for (int k = 0; k < (1 << shift); k++) lookup[(code << shift) | k] = (c << 5) | l;
		}
	}

	public int Decode(Bits bits) {
		int e = lookup[bits.Peek(maxBits)];
		bits.Skip(e & 31);
		return e >> 5;
	}
}

// Raw LZMA as chd_lzma_decompressor writes it: lc 3, lp 0, pb 2, no end marker, the whole
// output in one buffer (so the dictionary is the output). After LzmaSpec.cpp (public domain).
static class Lzma {
	const int LC = 3, PB = 2;
	static byte[] s; static int sp, send; static uint range, code;

	static void Norm() {
		if (range < (1u << 24)) {
			range <<= 8;
			code = (code << 8) | (sp < send ? s[sp] : 0u);
			sp++;
		}
	}

	static int Bit(ushort[] p, int i) {
		uint bound = (range >> 11) * p[i];
		int bit;
		if (code < bound) { p[i] += (ushort)((2048 - p[i]) >> 5); range = bound; bit = 0; }
		else { p[i] -= (ushort)(p[i] >> 5); code -= bound; range -= bound; bit = 1; }
		Norm();
		return bit;
	}

	static uint Direct(int n) {
		uint r = 0;
		while (n-- > 0) {
			range >>= 1;
			code -= range;
			uint t = 0u - (code >> 31);
			code += range & t;
			r = (r << 1) + (t + 1);
			Norm();
		}
		return r;
	}

	static int Tree(ushort[] p, int b, int bits) {
		int m = 1;
		for (int i = 0; i < bits; i++) m = (m << 1) + Bit(p, b + m);
		return m - (1 << bits);
	}

	static int Reverse(ushort[] p, int b, int bits) {
		int m = 1, sym = 0;
		for (int i = 0; i < bits; i++) {
			int bit = Bit(p, b + m);
			m = (m << 1) + bit;
			sym |= bit << i;
		}
		return sym;
	}

	// a length decoder: choice, choice2, low[16][8], mid[16][8], high[256] in one array
	static int Len(ushort[] p, int posState) {
		if (Bit(p, 0) == 0) return Tree(p, 2 + posState * 8, 3);
		if (Bit(p, 1) == 0) return 8 + Tree(p, 2 + 128 + posState * 8, 3);
		return 16 + Tree(p, 2 + 256, 8);
	}

	static ushort[] Probs(int n) { ushort[] p = new ushort[n]; for (int i = 0; i < n; i++) p[i] = 1024; return p; }

	public static void Decode(byte[] src, int o, int n, byte[] dst) {
		s = src; sp = o; send = o + n;
		if (n < 5 || src[o] != 0) throw new Exception("chd: bad LZMA stream");
		range = 0xFFFFFFFF; code = 0;
		sp++;
		for (int i = 0; i < 4; i++) code = (code << 8) | src[sp++];
		ushort[] lit = Probs(0x300 << LC);
		ushort[] isMatch = Probs(12 << 4), isRep0Long = Probs(12 << 4);
		ushort[] isRep = Probs(12), isRepG0 = Probs(12), isRepG1 = Probs(12), isRepG2 = Probs(12);
		ushort[] lenDec = Probs(2 + 256 + 256), repLenDec = Probs(2 + 256 + 256);
		ushort[] posSlot = Probs(4 << 6), posDec = Probs(115), align = Probs(16);
		uint rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;
		int state = 0, op = 0, size = dst.Length;
		while (op < size) {
			int posState = op & ((1 << PB) - 1);
			if (Bit(isMatch, (state << 4) + posState) == 0) {
				int prev = op > 0 ? dst[op - 1] : 0;
				int b = 0x300 * (prev >> (8 - LC));
				int sym = 1;
				if (state >= 7) {
					int match = dst[op - (int)rep0 - 1];
					do {
						int mb = (match >> 7) & 1;
						match <<= 1;
						int bit = Bit(lit, b + ((1 + mb) << 8) + sym);
						sym = (sym << 1) | bit;
						if (mb != bit) break;
					} while (sym < 0x100);
				}
				while (sym < 0x100) sym = (sym << 1) | Bit(lit, b + sym);
				dst[op++] = (byte)(sym - 0x100);
				state = state < 4 ? 0 : state < 10 ? state - 3 : state - 6;
				continue;
			}
			int len;
			if (Bit(isRep, state) != 0) {
				if (op == 0) throw new Exception("chd: bad LZMA stream");
				if (Bit(isRepG0, state) == 0) {
					if (Bit(isRep0Long, (state << 4) + posState) == 0) {
						state = state < 7 ? 9 : 11;
						dst[op] = dst[op - (int)rep0 - 1];
						op++;
						continue;
					}
				} else {
					uint dist;
					if (Bit(isRepG1, state) == 0) dist = rep1;
					else {
						if (Bit(isRepG2, state) == 0) dist = rep2;
						else { dist = rep3; rep3 = rep2; }
						rep2 = rep1;
					}
					rep1 = rep0;
					rep0 = dist;
				}
				len = Len(repLenDec, posState);
				state = state < 7 ? 8 : 11;
			} else {
				rep3 = rep2; rep2 = rep1; rep1 = rep0;
				len = Len(lenDec, posState);
				state = state < 7 ? 7 : 10;
				int slot = Tree(posSlot, (len < 3 ? len : 3) << 6, 6);
				if (slot < 4) rep0 = (uint)slot;
				else {
					int direct = (slot >> 1) - 1;
					uint dist = (uint)((2 | (slot & 1)) << direct);
					if (slot < 14) dist += (uint)Reverse(posDec, (int)dist - slot, direct);
					else {
						dist += Direct(direct - 4) << 4;
						dist += (uint)Reverse(align, 0, 4);
					}
					rep0 = dist;
				}
				if (rep0 == 0xFFFFFFFF) break;     // end marker
				if (rep0 >= op) throw new Exception("chd: bad LZMA distance");
			}
			len += 2;
			if (len > size - op) throw new Exception("chd: LZMA match past the hunk");
			int from = op - (int)rep0 - 1;
			for (int i = 0; i < len; i++) dst[op++] = dst[from + i];
		}
		if (op != size) throw new Exception("chd: LZMA data ends early");
		s = null;
	}
}

// The FLAC frames chd_cd_flac_compressor writes (no stream header: 44100 Hz, 2 channels,
// 16 bits); fills dst with big-endian interleaved samples and returns where the frames end.
static class Flac {
	static byte[] s; static long bp;

	static uint Read(int n) {
		uint v = 0;
		for (int i = 0; i < n; i++) {
			long at = bp >> 3;
			if (at >= s.Length) throw new Exception("chd: FLAC data ends early");
			v = (v << 1) | (uint)((s[at] >> (7 - (int)(bp & 7))) & 1);
			bp++;
		}
		return v;
	}

	static int Signed(int n) {
		if (n == 0) return 0;
		uint v = Read(n);
		return (int)(v << (32 - n)) >> (32 - n);
	}

	static long Signed64(int n) {      // a side channel can be 17 bits, raw samples up to 32
		if (n <= 31) return Signed(n);
		return (int)Read(32);
	}

	static int Unary() {
		int q = 0;
		while (Read(1) == 0) q++;
		return q;
	}

	public static int Decode(byte[] src, byte[] dst) {
		s = src; bp = 0;
		int total = dst.Length / 4, done = 0;
		while (done < total) done += Frame(dst, done, total);
		s = null;
		return (int)(bp >> 3);
	}

	static int Frame(byte[] dst, int at, int total) {
		if (Read(14) != 0x3FFE) throw new Exception("chd: bad FLAC frame");
		Read(2);
		int bsCode = (int)Read(4), srCode = (int)Read(4);
		int chan = (int)Read(4), ssCode = (int)Read(3);
		Read(1);
		// the frame / sample number, UTF-8 style
		uint lead = Read(8);
		int extra = 0;
		while ((lead & (0x80 >> extra)) != 0 && extra < 7) extra++;
		for (int i = 1; i < extra; i++) Read(8);
		int bs;
		if (bsCode == 1) bs = 192;
		else if (bsCode >= 2 && bsCode <= 5) bs = 576 << (bsCode - 2);
		else if (bsCode == 6) bs = (int)Read(8) + 1;
		else if (bsCode == 7) bs = (int)Read(16) + 1;
		else if (bsCode >= 8) bs = 256 << (bsCode - 8);
		else throw new Exception("chd: bad FLAC block size");
		if (srCode == 12) Read(8);
		else if (srCode == 13 || srCode == 14) Read(16);
		Read(8);                                          // header CRC-8
		int bps;
		switch (ssCode) {
			case 0: case 4: bps = 16; break;
			case 1: bps = 8; break;
			case 2: bps = 12; break;
			case 5: bps = 20; break;
			case 6: bps = 24; break;
			default: throw new Exception("chd: bad FLAC sample size");
		}
		if (chan != 1 && chan < 8 || chan > 10) throw new Exception("chd: FLAC isn't stereo");
		long[] a = Subframe(bs, bps + (chan == 9 ? 1 : 0));
		long[] b = Subframe(bs, bps + (chan == 8 || chan == 10 ? 1 : 0));
		if ((bp & 7) != 0) bp += 8 - (bp & 7);
		Read(16);                                         // frame CRC-16
		int n = Math.Min(bs, total - at);
		for (int i = 0; i < n; i++) {
			long l = a[i], r = b[i];
			if (chan == 8) r = l - r;                     // left / side
			else if (chan == 9) l = l + r;                // side / right: a = side
			else if (chan == 10) {                        // mid / side
				long mid = (a[i] << 1) | (b[i] & 1);
				l = (mid + b[i]) >> 1;
				r = (mid - b[i]) >> 1;
			}
			int o = (at + i) * 4;
			dst[o] = (byte)(l >> 8); dst[o + 1] = (byte)l;
			dst[o + 2] = (byte)(r >> 8); dst[o + 3] = (byte)r;
		}
		return bs;
	}

	static long[] Subframe(int bs, int bps) {
		Read(1);
		int type = (int)Read(6);
		int wasted = 0;
		if (Read(1) == 1) wasted = Unary() + 1;
		bps -= wasted;
		long[] x = new long[bs];
		if (type == 0) {
			long v = Signed64(bps);
			for (int i = 0; i < bs; i++) x[i] = v;
		} else if (type == 1) {
			for (int i = 0; i < bs; i++) x[i] = Signed64(bps);
		} else if (type >= 8 && type <= 12) {
			int order = type - 8;
			for (int i = 0; i < order; i++) x[i] = Signed64(bps);
			Residual(x, bs, order);
			for (int i = order; i < bs; i++) {
				switch (order) {
					case 1: x[i] += x[i - 1]; break;
					case 2: x[i] += 2 * x[i - 1] - x[i - 2]; break;
					case 3: x[i] += 3 * x[i - 1] - 3 * x[i - 2] + x[i - 3]; break;
					case 4: x[i] += 4 * x[i - 1] - 6 * x[i - 2] + 4 * x[i - 3] - x[i - 4]; break;
				}
			}
		} else if (type >= 32) {
			int order = (type & 31) + 1;
			for (int i = 0; i < order; i++) x[i] = Signed64(bps);
			int prec = (int)Read(4) + 1;
			if (prec == 16) throw new Exception("chd: bad FLAC LPC precision");
			int shift = Signed(5);
			long[] c = new long[order];
			for (int i = 0; i < order; i++) c[i] = Signed(prec);
			Residual(x, bs, order);
			for (int i = order; i < bs; i++) {
				long sum = 0;
				for (int j = 0; j < order; j++) sum += c[j] * x[i - j - 1];
				x[i] += sum >> shift;
			}
		} else throw new Exception("chd: bad FLAC subframe");
		if (wasted > 0) for (int i = 0; i < bs; i++) x[i] <<= wasted;
		return x;
	}

	static void Residual(long[] x, int bs, int order) {
		int method = (int)Read(2);
		if (method > 1) throw new Exception("chd: bad FLAC residual");
		int pbits = method == 0 ? 4 : 5, escape = method == 0 ? 15 : 31;
		int porder = (int)Read(4);
		int parts = 1 << porder, i = order;
		for (int p = 0; p < parts; p++) {
			int n = (bs >> porder) - (p == 0 ? order : 0);
			int k = (int)Read(pbits);
			if (k == escape) {
				int raw = (int)Read(5);
				for (int j = 0; j < n; j++) x[i++] = Signed(raw);
			} else {
				for (int j = 0; j < n; j++) {
					uint v = ((uint)Unary() << k) | Read(k);
					x[i++] = (long)(v >> 1) ^ -(long)(v & 1);
				}
			}
		}
	}
}

// cdrom.cpp's ECC: P and Q parity over the sector from its header (a mode 2 header counts as
// zeros), rebuilt for the sectors chdman stored without it.
static class Ecc {
	static byte[] fwd, back;

	static void Tables() {
		fwd = new byte[256]; back = new byte[256];
		for (int i = 0; i < 256; i++) {
			int j = (i << 1) ^ ((i & 0x80) != 0 ? 0x11D : 0);
			fwd[i] = (byte)j;
			back[i ^ j] = (byte)i;
		}
	}

	static byte Src(byte[] d, int s, int o) {
		return d[s + 15] == 2 && o < 4 ? (byte)0 : d[s + 12 + o];
	}

	static void Block(byte[] d, int s, int majors, int minors, int mult, int inc, int dest) {
		int size = majors * minors;
		for (int major = 0; major < majors; major++) {
			int idx = (major >> 1) * mult + (major & 1);
			byte a = 0, b = 0;
			for (int minor = 0; minor < minors; minor++) {
				byte t = Src(d, s, idx);
				idx += inc;
				if (idx >= size) idx -= size;
				a ^= t; b ^= t;
				a = fwd[a];
			}
			a = back[fwd[a] ^ b];
			d[s + dest + major] = a;
			d[s + dest + major + majors] = (byte)(a ^ b);
		}
	}

	public static void Generate(byte[] d, int s) {
		if (fwd == null) Tables();
		Block(d, s, 86, 24, 2, 86, 0x81C);
		Block(d, s, 52, 43, 86, 88, 0x8C8);
	}
}
