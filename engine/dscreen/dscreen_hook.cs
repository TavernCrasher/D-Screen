// D-Screen's Claude Code hook (docs/desktop_pet.md "Claude Code hooks", docs/shareable_pet_plan.md
// step 8): the shareable pet's stand-in for tools/pet_hook.py, so the player needs no Python.
// Built by tools/pet_export.py with Windows' own C# compiler (.NET Framework 4, C# 5).
//
//   dscreen-hook.exe              the hook: reads Claude Code's JSON on stdin and appends one line
//                                 to %APPDATA%\D-Screen\pet_events.jsonl, which the pet polls.
//                                 Never fails: any error is swallowed (exit 0).
//   dscreen-hook.exe --install    adds the hook (async, five events) to Claude Code's
//                                 settings.json, after a backup beside it; any earlier D-Screen
//                                 entries are replaced, everything else is kept as it was.
//   dscreen-hook.exe --uninstall  removes D-Screen's entries (and only those), after a backup.
//   --settings=<path>             another settings.json (tests); --events=<path> another feed.
//
// Exit codes (install / uninstall): 0 done or nothing to do, 1 settings.json isn't valid JSON
// (left untouched), 2 can't read or write it, 3 no Claude Code folder.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class DScreenHook
{
    static readonly string[] EVENTS = { "UserPromptSubmit", "Stop", "StopFailure", "Notification", "PostToolUseFailure" };
    const string MARK = "dscreen-hook";          // how D-Screen's own entries are recognised
    const long MAX_BYTES = 64 * 1024;            // the feed is trimmed to its last KEEP lines past this
    const int KEEP = 50;

    [DllImport("kernel32.dll")]
    static extern void GetSystemTimePreciseAsFileTime(out long fileTime);

    // Unix seconds to the microsecond: the pet skips an event no later than the last one it took,
    // so two hooks in one coarse DateTime tick must not share a time (DS8-6).
    static double UnixNow()
    {
        long ft;
        try { GetSystemTimePreciseAsFileTime(out ft); }
        catch (Exception) { ft = DateTime.UtcNow.ToFileTimeUtc(); }      // before Windows 8
        return (ft - 116444736000000000L) / 1e7;
    }

    static int Main(string[] args)
    {
        string settings = null, events = null, mode = "hook";
        foreach (string a in args)
        {
            if (a == "--install" || a == "--uninstall") mode = a.Substring(2);
            else if (a.StartsWith("--settings=")) settings = a.Substring(11);
            else if (a.StartsWith("--events=")) events = a.Substring(9);
        }
        if (mode == "hook")
        {
            try { Hook(events ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "D-Screen", "pet_events.jsonl")); }
            catch (Exception) { }
            return 0;
        }
        if (settings == null)
        {
            string dir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrEmpty(dir))
                dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            if (!Directory.Exists(dir))
            {
                Console.WriteLine("no Claude Code folder: " + dir);
                return 3;
            }
            settings = Path.Combine(dir, "settings.json");
        }
        string exe = System.Reflection.Assembly.GetExecutingAssembly().Location.Replace('\\', '/');
        return Edit(settings, mode == "install" ? "\"" + exe + "\"" : null);
    }

    // ------------------------------------------------------------ the hook
    static void Hook(string path)
    {
        path = Path.GetFullPath(path);
        string text = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false)).ReadToEnd();
        Json.Obj d = Json.Parse(text) as Json.Obj;
        if (d == null) return;
        var ev = new Json.Obj();
        ev.Set("t", new Json.Raw(UnixNow().ToString("0.000000", CultureInfo.InvariantCulture)));
        ev.Set("event", d.Str("hook_event_name"));
        ev.Set("type", d.Str("notification_type"));
        ev.Set("tool", d.Str("tool_name"));
        ev.Set("session", d.Str("session_id"));
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        byte[] line = new UTF8Encoding(false).GetBytes(Json.Write(ev, -1) + "\n");
        for (int attempt = 0; ; attempt++)          // shared, as Python's append is: hooks run side by side
        {
            try
            {
                using (var f = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
                    f.Write(line, 0, line.Length);
                break;
            }
            catch (Exception e)
            {
                if (attempt >= 20 || !(e is IOException || e is UnauthorizedAccessException)) throw;
                Thread.Sleep(10);
            }
        }
        if (new FileInfo(path).Length > MAX_BYTES)
        {
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            int from = Math.Max(0, lines.Length - KEEP);
            var keep = new StringBuilder();
            for (int i = from; i < lines.Length; i++) keep.Append(lines[i]).Append('\n');
            File.WriteAllText(path, keep.ToString(), new UTF8Encoding(false));
        }
    }

    // ------------------------------------------------------------ settings.json
    // command != null: install that command; null: uninstall.
    static int Edit(string path, string command)
    {
        string text = "";
        bool exists = File.Exists(path);
        try { if (exists) text = File.ReadAllText(path, Encoding.UTF8); }
        catch (Exception e) { Console.WriteLine("can't read " + path + ": " + e.Message); return 2; }
        Json.Obj root;
        if (text.Trim().Length == 0) root = new Json.Obj();
        else
        {
            try { root = Json.Parse(text) as Json.Obj; }
            catch (Exception e) { Console.WriteLine("settings.json isn't valid JSON, left as it is: " + e.Message); return 1; }
            if (root == null) { Console.WriteLine("settings.json isn't a JSON object, left as it is"); return 1; }
        }
        Json.Obj hooks = root.Get("hooks") as Json.Obj;
        if (root.Get("hooks") != null && hooks == null) { Console.WriteLine("settings.json's \"hooks\" isn't an object, left as it is"); return 1; }
        bool changed = Remove(root, hooks);
        if (command != null)
        {
            if (hooks == null || root.Get("hooks") == null)
            {
                hooks = new Json.Obj();
                root.Set("hooks", hooks);
            }
            foreach (string ev in EVENTS)
            {
                var list = hooks.Get(ev) as List<object>;
                if (list == null && hooks.Get(ev) != null)
                {
                    Console.WriteLine("settings.json's \"hooks\"." + ev + " isn't a list, left as it is");
                    return 1;
                }
                if (list == null)
                {
                    list = new List<object>();
                    hooks.Set(ev, list);
                }
                var h = new Json.Obj();
                h.Set("type", "command");
                h.Set("command", command);
                h.Set("async", new Json.Raw("true"));
                h.Set("timeout", new Json.Raw("10"));
                var group = new Json.Obj();
                group.Set("hooks", new List<object> { h });
                list.Add(group);
            }
            changed = true;
        }
        if (!changed) { Console.WriteLine("nothing to remove"); return 0; }
        string nl = text.Contains("\r\n") ? "\r\n" : "\n";
        string output = Json.Write(root, 0).Replace("\n", nl) + (text.Length == 0 || text.EndsWith("\n") ? nl : "");
        string tmp = path + ".dscreen-tmp";
        try
        {
            if (exists && File.ReadAllText(path, Encoding.UTF8) != text)
            {
                Console.WriteLine("settings.json changed while it was being edited; nothing written, try again");
                return 2;
            }
            if (exists)
            {
                string stem = path + ".bak-dscreen-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture), backup = stem;
                for (int n = 2; File.Exists(backup); n++) backup = stem + "-" + n;    // never over an earlier one
                File.Copy(path, backup);
                Console.WriteLine("backup: " + backup);
            }
            File.WriteAllText(tmp, output, new UTF8Encoding(false));
            if (exists) File.Replace(tmp, path, null);
            else File.Move(tmp, path);
        }
        catch (Exception e)
        {
            Console.WriteLine("can't write " + path + ": " + e.Message);
            try { if (File.Exists(tmp)) File.Delete(tmp); } catch (Exception) { }
            return 2;
        }
        Console.WriteLine((command != null ? "installed in " : "removed from ") + path);
        return 0;
    }

    // Takes D-Screen's hooks out of every event; a group or event left empty by that goes too,
    // and "hooks" itself when nothing is left in it. True if anything was removed.
    static bool Remove(Json.Obj root, Json.Obj hooks)
    {
        if (hooks == null) return false;
        bool any = false;
        foreach (string ev in new List<string>(hooks.Keys()))
        {
            var groups = hooks.Get(ev) as List<object>;
            if (groups == null) continue;
            int before = groups.Count;
            for (int g = groups.Count - 1; g >= 0; g--)
            {
                var group = groups[g] as Json.Obj;
                var list = group == null ? null : group.Get("hooks") as List<object>;
                if (list == null) continue;
                int n = list.RemoveAll(o => o is Json.Obj && ((Json.Obj)o).Str("command").IndexOf(MARK, StringComparison.OrdinalIgnoreCase) >= 0);
                if (n > 0)
                {
                    any = true;
                    if (list.Count == 0) groups.RemoveAt(g);
                }
            }
            if (groups.Count == 0 && before > 0) hooks.Remove(ev);
        }
        if (any && hooks.Count == 0) root.Remove("hooks");
        return any;
    }
}

// A small JSON reader and writer that keeps the file's key order and number spellings, and writes
// as Claude Code does (JSON.stringify(x, null, 2)).
static class Json
{
    public class Raw { public string Text; public Raw(string t) { Text = t; } }   // number, true, false, null

    public class Obj
    {
        readonly List<KeyValuePair<string, object>> items = new List<KeyValuePair<string, object>>();
        public int Count { get { return items.Count; } }
        public object Get(string k)
        {
            foreach (var kv in items) if (kv.Key == k) return kv.Value;
            return null;
        }
        public string Str(string k) { return Get(k) as string ?? ""; }
        public void Set(string k, object v)
        {
            for (int i = 0; i < items.Count; i++)
                if (items[i].Key == k) { items[i] = new KeyValuePair<string, object>(k, v); return; }
            items.Add(new KeyValuePair<string, object>(k, v));
        }
        public void Remove(string k) { items.RemoveAll(kv => kv.Key == k); }
        public List<string> Keys() { var l = new List<string>(); foreach (var kv in items) l.Add(kv.Key); return l; }
        public List<KeyValuePair<string, object>> Items() { return items; }
    }

    public static object Parse(string s)
    {
        int i = 0;
        if (s.Length > 0 && s[0] == '﻿') i = 1;
        object v = Value(s, ref i);
        Ws(s, ref i);
        if (i != s.Length) throw new FormatException("text after the value at " + i);
        return v;
    }

    static void Ws(string s, ref int i) { while (i < s.Length && " \t\r\n".IndexOf(s[i]) >= 0) i++; }

    static object Value(string s, ref int i)
    {
        Ws(s, ref i);
        if (i >= s.Length) throw new FormatException("unexpected end");
        char c = s[i];
        if (c == '{')
        {
            var o = new Obj();
            i++;
            Ws(s, ref i);
            if (i < s.Length && s[i] == '}') { i++; return o; }
            while (true)
            {
                Ws(s, ref i);
                if (i >= s.Length || s[i] != '"') throw new FormatException("expected a key at " + i);
                string k = Str(s, ref i);
                Ws(s, ref i);
                if (i >= s.Length || s[i] != ':') throw new FormatException("expected ':' at " + i);
                i++;
                o.Set(k, Value(s, ref i));
                Ws(s, ref i);
                if (i < s.Length && s[i] == ',') { i++; continue; }
                if (i < s.Length && s[i] == '}') { i++; return o; }
                throw new FormatException("expected ',' or '}' at " + i);
            }
        }
        if (c == '[')
        {
            var l = new List<object>();
            i++;
            Ws(s, ref i);
            if (i < s.Length && s[i] == ']') { i++; return l; }
            while (true)
            {
                l.Add(Value(s, ref i));
                Ws(s, ref i);
                if (i < s.Length && s[i] == ',') { i++; continue; }
                if (i < s.Length && s[i] == ']') { i++; return l; }
                throw new FormatException("expected ',' or ']' at " + i);
            }
        }
        if (c == '"') return Str(s, ref i);
        int start = i;
        while (i < s.Length && "+-0123456789.eEtruefalsn".IndexOf(s[i]) >= 0) i++;
        string tok = s.Substring(start, i - start);
        double dummy;
        if (tok == "true" || tok == "false" || tok == "null" ||
            (tok.Length > 0 && double.TryParse(tok, NumberStyles.Float, CultureInfo.InvariantCulture, out dummy)))
            return new Raw(tok);
        throw new FormatException("bad value at " + start);
    }

    static string Str(string s, ref int i)
    {
        var b = new StringBuilder();
        i++;                                                    // the opening quote
        while (true)
        {
            if (i >= s.Length) throw new FormatException("unterminated string");
            char c = s[i++];
            if (c == '"') return b.ToString();
            if (c != '\\') { b.Append(c); continue; }
            if (i >= s.Length) throw new FormatException("unterminated string");
            char e = s[i++];
            switch (e)
            {
                case '"': b.Append('"'); break;
                case '\\': b.Append('\\'); break;
                case '/': b.Append('/'); break;
                case 'b': b.Append('\b'); break;
                case 'f': b.Append('\f'); break;
                case 'n': b.Append('\n'); break;
                case 'r': b.Append('\r'); break;
                case 't': b.Append('\t'); break;
                case 'u':
                    if (i + 4 > s.Length) throw new FormatException("bad \\u escape");
                    b.Append((char)int.Parse(s.Substring(i, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                    i += 4;
                    break;
                default: throw new FormatException("bad escape at " + i);
            }
        }
    }

    // indent < 0: one line (the feed's lines); else JSON.stringify's two-space layout.
    public static string Write(object v, int indent)
    {
        var b = new StringBuilder();
        Emit(b, v, indent);
        return b.ToString();
    }

    static void Emit(StringBuilder b, object v, int ind)
    {
        string pad = ind < 0 ? "" : "\n" + new string(' ', (ind + 1) * 2), end = ind < 0 ? "" : "\n" + new string(' ', ind * 2);
        int next = ind < 0 ? -1 : ind + 1;
        if (v is Obj)
        {
            var items = ((Obj)v).Items();
            if (items.Count == 0) { b.Append("{}"); return; }
            b.Append('{');
            for (int k = 0; k < items.Count; k++)
            {
                if (k > 0) b.Append(ind < 0 ? ", " : ",");
                b.Append(pad);
                Quote(b, items[k].Key);
                b.Append(": ");
                Emit(b, items[k].Value, next);
            }
            b.Append(end).Append('}');
        }
        else if (v is List<object>)
        {
            var l = (List<object>)v;
            if (l.Count == 0) { b.Append("[]"); return; }
            b.Append('[');
            for (int k = 0; k < l.Count; k++)
            {
                if (k > 0) b.Append(ind < 0 ? ", " : ",");
                b.Append(pad);
                Emit(b, l[k], next);
            }
            b.Append(end).Append(']');
        }
        else if (v is Raw) b.Append(((Raw)v).Text);
        else Quote(b, v as string ?? "");
    }

    static void Quote(StringBuilder b, string s)
    {
        b.Append('"');
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': b.Append("\\\""); break;
                case '\\': b.Append("\\\\"); break;
                case '\b': b.Append("\\b"); break;
                case '\f': b.Append("\\f"); break;
                case '\n': b.Append("\\n"); break;
                case '\r': b.Append("\\r"); break;
                case '\t': b.Append("\\t"); break;
                default:
                    if (c < 0x20) b.Append("\\u").Append(((int)c).ToString("x4"));
                    else b.Append(c);
                    break;
            }
        }
        b.Append('"');
    }
}
