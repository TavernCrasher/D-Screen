// DuckStation, watched read-only (docs/memcard_bridge.md section 15.3; D-Screen): compiled into the
// pet's helper with pet_helper.cs. The pet starts it with "duck <hex> <ram offset> [process name]":
// <hex> is a stretch of the player's own EXE as it sits in PS1 RAM at <ram offset> (hex), which
// finds DW1's RAM inside DuckStation's process (as speedrun autosplitters do). Over stdout, on change:
//   "d 0" | "d <pid>"                      DuckStation closed | running
//   "m -" | "m <slot> <card> <screen> <type> <raised> <name> <record>"
//                                          DW1 not in its RAM (BIOS, another game, not found yet) |
//                                          MEMORY_CARD_SLOT 0x8013503C (-1 none), MEMORY_CARD_ID
//                                          0x80135044 (0 port 1, 0x10 port 2, -1 none), the screen
//                                          (map id) 0x80134DA8, the partner's type 0x801557A8, the
//                                          raised count 0x801557A5, Digimon entry 0's name (the
//                                          tamer's once a save loads; 20 bytes, hex) at 0x8012CEB4,
//                                          and the spare record Continue read in (copy 0 + 0x4E4 of
//                                          the card buffer 0x8013192C: 0x80132010, 24 bytes, hex).
// The slot and port are 0 / 0 from boot (BSS), so a save counts as loaded only by its name.
// It only ever reads (OpenProcess with PROCESS_QUERY_INFORMATION | PROCESS_VM_READ); nothing is
// written, and DuckStation needs no setting.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

static class DuckWatch {
	[DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
	[DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
	[DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr at, byte[] buf, IntPtr n, out IntPtr read);
	[DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr at, out MBI info, IntPtr size);
	[StructLayout(LayoutKind.Sequential)] struct MBI {
		public IntPtr BaseAddress, AllocationBase;
		public uint AllocationProtect;
		public IntPtr RegionSize;
		public uint State, Protect, Type;
	}
	const uint QUERY = 0x0400, VM_READ = 0x0010, COMMIT = 0x1000, GUARD = 0x100, NOACCESS = 0x01;
	const int SLOT = 0x13503C, CARD = 0x135044, SCREEN = 0x134DA8, TYPE = 0x1557A8, RAISED = 0x1557A5,
		NAME = 0x12CEB4, RECORD = 0x132010;

	static byte[] pattern;
	static long patternAt;
	static string procName = "duckstation";
	static Action<string> say;

	public static void Start(string[] a, Action<string> sayFn) {
		pattern = Hex(a[1]);
		patternAt = Convert.ToInt64(a[2], 16);
		if (a.Length > 3) procName = a[3].ToLowerInvariant();
		say = sayFn;
		Thread t = new Thread(Run);
		t.IsBackground = true;
		t.Start();
	}

	static byte[] Hex(string s) {
		byte[] b = new byte[s.Length / 2];
		for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(s.Substring(2 * i, 2), 16);
		return b;
	}

	static void Run() {
		int pid = 0;
		IntPtr h = IntPtr.Zero;
		long ram = 0;
		long nextScan = 0;
		string lastD = null, lastM = null;
		Stopwatch clock = Stopwatch.StartNew();
		for (;;) {
			int now = Find();
			if (now != pid) {
				if (h != IntPtr.Zero) CloseHandle(h);
				h = now != 0 ? OpenProcess(QUERY | VM_READ, false, now) : IntPtr.Zero;
				pid = now;
				ram = 0;
				nextScan = 0;
			}
			string d = pid != 0 ? "d " + pid : "d 0";
			if (d != lastD) { say(d); lastD = d; }
			string m = "m -";
			if (h != IntPtr.Zero) {
				if (ram != 0 && !Matches(h, ram)) ram = 0;          // a new game booted, RAM moved
				if (ram == 0 && clock.ElapsedMilliseconds >= nextScan) {
					ram = Scan(h);
					nextScan = clock.ElapsedMilliseconds + 5000;
				}
				if (ram != 0) {
					byte[] b = new byte[4];
					m = "m " + I32(h, ram + SLOT, b) + " " + I32(h, ram + CARD, b) + " " + U8(h, ram + SCREEN, b)
						+ " " + I32(h, ram + TYPE, b) + " " + U8(h, ram + RAISED, b) + " " + Hex(h, ram + NAME, 20)
						+ " " + Hex(h, ram + RECORD, 24);
				}
			}
			if (m != lastM) { say(m); lastM = m; }
			Thread.Sleep(1000);
		}
	}

	static int Find() {
		foreach (Process p in Process.GetProcesses()) {
			try {
				if (p.ProcessName.ToLowerInvariant().StartsWith(procName)) return p.Id;
			} catch { }
		}
		return 0;
	}

	static bool Read(IntPtr h, long at, byte[] buf) {
		IntPtr n;
		return ReadProcessMemory(h, new IntPtr(at), buf, new IntPtr(buf.Length), out n) && n.ToInt64() == buf.Length;
	}

	static bool Matches(IntPtr h, long ram) {
		byte[] b = new byte[pattern.Length];
		if (!Read(h, ram + patternAt, b)) return false;
		for (int i = 0; i < b.Length; i++) if (b[i] != pattern[i]) return false;
		return true;
	}

	// Every committed, readable region's base and allocation base: the first whose bytes at the
	// pattern's offset are the EXE's. Not only regions of the RAM's size: the recompiler may
	// protect code pages, which splits the RAM's mapping into smaller regions (CARD-4); a read
	// spans regions of different protection.
	static long Scan(IntPtr h) {
		long at = 0;
		MBI mi;
		IntPtr size = new IntPtr(Marshal.SizeOf(typeof(MBI)));
		System.Collections.Generic.HashSet<long> tried = new System.Collections.Generic.HashSet<long>();
		while (VirtualQueryEx(h, new IntPtr(at), out mi, size) != IntPtr.Zero) {
			long b = mi.BaseAddress.ToInt64(), n = mi.RegionSize.ToInt64();
			if (mi.State == COMMIT && (mi.Protect & GUARD) == 0 && mi.Protect != NOACCESS) {
				foreach (long c in new long[] { mi.AllocationBase.ToInt64(), b }) {
					if (c != 0 && tried.Add(c) && Matches(h, c)) return c;
				}
			}
			if (n <= 0) break;
			at = b + n;
		}
		return 0;
	}

	static int I32(IntPtr h, long at, byte[] b) {
		return Read(h, at, b) ? BitConverter.ToInt32(b, 0) : -1;
	}

	static string Hex(IntPtr h, long at, int n) {
		byte[] b = new byte[n];
		return Read(h, at, b) ? BitConverter.ToString(b).Replace("-", "").ToLowerInvariant() : "-";
	}

	static int U8(IntPtr h, long at, byte[] b) {
		return Read(h, at, b) ? b[0] : -1;
	}
}
