// The desktop pet's helper (docs/desktop_pet.md), compiled by the pet itself with Windows' own
// C# compiler (csc.exe, .NET Framework 4) into user://pet_helper.exe. Over its stdout:
//   "w L T R B;L T R B;..."  every visible, unminimized, titled top-level window, topmost first
//                            (EnumWindows z-order), DWM extended frame bounds in physical pixels
//                            (per-monitor DPI aware, so they match Godot's); only when it changes.
//                            Skips tool windows, click-through overlays, cloaked windows and the pet.
//   "t L T R B;..."          the taskbars (Shell_TrayWnd, Shell_SecondaryTrayWnd), only when they
//                            change: an auto-hidden one slides up and down, and he rides it.
//                            The taskbars, the foreground window (the one being dragged) and the
//                            window he stands on are checked every 15 ms; the window list every
//                            200 ms, at once when one of them moved, and every 15 ms for a second after any change, so he slides
//                            with a window that moves instead of jumping.
//   "i <ms>"                 milliseconds since the last keyboard or mouse input (GetLastInputInfo).
//   "c <x> <y>"              a mouse button pressed anywhere (GetAsyncKeyState, polled every 30 ms),
//                            at the cursor in physical pixels: the pet closes its menu on a click
//                            elsewhere, which its click-through window never receives.
// On its stdin: "pass <hwnd> 1|0" makes the pet's window click-through (WS_EX_LAYERED +
// WS_EX_TRANSPARENT; Godot's passthrough flag only passes clicks to its own windows) or not;
// "top <hwnd>" raises it over the pet's other windows (his props and piles) without touching its
// flags (Godot hides a window whose always-on-top flag is toggled); "ride L T R B" names the window
// he stands on by its rect from the last list ("ride" alone: the taskbar), so a window moved by its
// own program, not dragged, is followed as quickly as the foreground one.
// It exits when stdin closes or the pet's process ends.
// "duck <hex> <ram offset> [name]" starts the read-only DuckStation watch (pet_duck.cs): "d" and "m" lines.
// Run as "chd <image> [pid]" it reads a CHD disc image instead (pet_chd.cs, compiled with it).
using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;

static class PetHelper {
	delegate bool EnumProc(IntPtr h, IntPtr l);
	[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
	[DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
	[DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
	[DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
	[DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte a, uint f);
	[DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint f);
	[DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
	[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
	[DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
	[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LastInput li);
	[DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
	[DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr p, IntPtr after, string cls, string title);
	[DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
	[DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
	[DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
	[DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
	[StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
	[StructLayout(LayoutKind.Sequential)] struct LastInput { public uint size; public uint time; }
	[StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }

	static readonly object Out = new object();
	static readonly object RideLock = new object();
	static string rideRect = "";                             // "L T R B" of the window he stands on, "" none
	static string lastRects = "";                            // the last scan's rects ...
	static IntPtr[] lastHwnds = new IntPtr[0];               // ... and their windows

	static void Say(string s) {
		lock (Out) {
			try { Console.Out.WriteLine(s); Console.Out.Flush(); } catch { Environment.Exit(0); }
		}
	}

	static void Commands() {
		string line;
		while ((line = Console.In.ReadLine()) != null) {
			string[] a = line.Trim().Split(' ');
			if (a.Length == 3 && a[0] == "pass") {
				IntPtr h = new IntPtr(long.Parse(a[1]));
				int ex = GetWindowLong(h, -20);
				if (a[2] == "1") {
					bool layered = (ex & 0x80000) != 0;
					SetWindowLong(h, -20, ex | 0x80020);
					if (!layered) SetLayeredWindowAttributes(h, 0, 255, 2);   // LWA_ALPHA: fully drawn
				} else {
					SetWindowLong(h, -20, ex & ~0x20);
				}
			} else if (a[0] == "ride") {
				lock (RideLock) rideRect = a.Length == 5 ? a[1] + " " + a[2] + " " + a[3] + " " + a[4] : "";
			} else if (a.Length == 2 && a[0] == "top") {
				// HWND_TOPMOST; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
				SetWindowPos(new IntPtr(long.Parse(a[1])), new IntPtr(-1), 0, 0, 0, 0, 0x13);
			} else if (a.Length >= 3 && a[0] == "duck") {
				DuckWatch.Start(a, Say);                       // pet_duck.cs: DuckStation, read-only
			}
		}
		Environment.Exit(0);                                   // stdin closed: the pet is gone
	}

	static void Clicks() {
		bool was = false;
		for (;;) {
			bool down = (GetAsyncKeyState(1) & 0x8000) != 0 || (GetAsyncKeyState(2) & 0x8000) != 0;
			if (down && !was) {
				POINT p;
				if (GetCursorPos(out p)) Say("c " + p.X + " " + p.Y);
			}
			was = down;
			Thread.Sleep(30);
		}
	}

	static string rideFor = "";                              // the rect rideHwnd was found by
	static IntPtr rideHwnd = IntPtr.Zero;

	// The window he stands on, found by its rect in the last scan and kept while it moves (the pet
	// names its new rect after each list).
	static IntPtr RideWindow() {
		string want;
		lock (RideLock) want = rideRect;
		if (want == "") { rideFor = ""; rideHwnd = IntPtr.Zero; return IntPtr.Zero; }
		if (want == rideFor) return rideHwnd;
		string[] r = lastRects.Split(';');
		for (int i = 0; i < r.Length && i < lastHwnds.Length; i++)
			if (r[i] == want) { rideFor = want; rideHwnd = lastHwnds[i]; break; }
		return rideHwnd;
	}

	static string Windows(int pet) {
		StringBuilder sb = new StringBuilder("w ");
		System.Collections.Generic.List<IntPtr> hwnds = new System.Collections.Generic.List<IntPtr>();
		EnumWindows(delegate (IntPtr h, IntPtr l) {
			if (!IsWindowVisible(h) || IsIconic(h) || GetWindowTextLength(h) == 0) return true;
			int ex = GetWindowLong(h, -20);
			if ((ex & 0x80) != 0 || (ex & 0x20) != 0) return true;   // WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT
			int cloaked;
			if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
			uint pid;
			GetWindowThreadProcessId(h, out pid);
			if ((int)pid == pet) return true;
			RECT r;
			if (DwmGetWindowAttribute(h, 9, out r, 16) != 0) return true;   // DWMWA_EXTENDED_FRAME_BOUNDS
			if (r.R - r.L < 80 || r.B - r.T < 40) return true;
			sb.Append(r.L).Append(' ').Append(r.T).Append(' ').Append(r.R).Append(' ').Append(r.B).Append(';');
			hwnds.Add(h);
			return true;
		}, IntPtr.Zero);
		lastRects = sb.ToString().Substring(2);
		lastHwnds = hwnds.ToArray();
		return sb.ToString();
	}

	static string Taskbars() {
		StringBuilder sb = new StringBuilder("t ");
		foreach (string cls in new string[] { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" }) {
			IntPtr h = IntPtr.Zero;
			while ((h = FindWindowEx(IntPtr.Zero, h, cls, null)) != IntPtr.Zero) {
				RECT r;
				if (!IsWindowVisible(h) || !GetWindowRect(h, out r)) continue;
				sb.Append(r.L).Append(' ').Append(r.T).Append(' ').Append(r.R).Append(' ').Append(r.B).Append(';');
			}
		}
		return sb.ToString();
	}

	static void Main(string[] args) {
		if (args.Length > 1 && args[0] == "chd") {                // a CHD disc image (pet_chd.cs)
			ChdServer.Run(args);
			return;
		}
		int pet = args.Length > 0 ? int.Parse(args[0]) : 0;
		SetProcessDpiAwarenessContext(new IntPtr(-4));          // per-monitor v2
		Thread t = new Thread(Commands);
		t.IsBackground = true;
		t.Start();
		Thread c = new Thread(Clicks);
		c.IsBackground = true;
		c.Start();
		string last = null, lastBars = null, lastFront = null, lastRide = null;
		long idle = -2000, check = -1000, scan = -1000, fast = -1;   // ms: the last idle report, process check, scan, change
		System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
		timeBeginPeriod(1);                                // 15 ms sleeps, not the default 15.6 ms ticks rounded up
		for (;;) {
			long now = clock.ElapsedMilliseconds;
			if (pet != 0 && now - check >= 1000) {
				check = now;
				try { if (System.Diagnostics.Process.GetProcessById(pet).HasExited) return; }
				catch { return; }
			}
			string bars = Taskbars();
			RECT fr;
			IntPtr fg = GetForegroundWindow();
			string front = fg != IntPtr.Zero && DwmGetWindowAttribute(fg, 9, out fr, 16) == 0
				? fg + " " + fr.L + " " + fr.T + " " + fr.R + " " + fr.B : "";
			RECT rr;
			IntPtr rw = RideWindow();
			string ride = rw != IntPtr.Zero && DwmGetWindowAttribute(rw, 9, out rr, 16) == 0
				? rr.L + " " + rr.T + " " + rr.R + " " + rr.B : "";
			int ck;                                        // hidden, minimized or cloaked keeps its rect:
			if (rw != IntPtr.Zero && (!IsWindowVisible(rw) || IsIconic(rw)       // a change now, not at the
					|| (DwmGetWindowAttribute(rw, 14, out ck, 4) == 0 && ck != 0)))   // next 200 ms scan (9d 12)
				ride = "gone";
			bool moved = bars != lastBars || front != lastFront || ride != lastRide;
			lastFront = front;
			lastRide = ride;
			if (!moved && fast < 0 && now - scan < 200) {
				Thread.Sleep(15);
				continue;
			}
			scan = now;
			string w = Windows(pet);
			if (w != last || bars != lastBars) {
				if (w != last) Say(w);
				if (bars != lastBars) Say(bars);
				last = w;
				lastBars = bars;
				fast = now;
			} else if (fast >= 0 && now - fast > 1000) {
				fast = -1;
			}
			if (now - idle >= 2000) {
				idle = now;
				LastInput li = new LastInput();
				li.size = 8;
				GetLastInputInfo(ref li);
				Say("i " + unchecked((uint)Environment.TickCount - li.time));
			}
			Thread.Sleep(15);
		}
	}
}
