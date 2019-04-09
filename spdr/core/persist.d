module spdr.core.persist;

import spdr.core.base;
import asdf.serialization : serializeToJson, deserialize;

///
void persistToFile(alias Serialize)(ref State s, string filename)
		if (is(typeof(Serialize(s)) == ubyte[]))
{
	import std.stdio : File;
	State.CacheEntry[string] ce;
	foreach(p; s.cache.byKeyValue) {
		if (p.value.persistent) {
			ce[p.key] = p.value;
		}
	}

	State tmp = s;
	tmp.cache = ce;

	auto data = Serialize(tmp);
	auto outf = File(filename, "w");
	outf.rawWrite(data);
}

///
ubyte[] toBytes(alias fn)(ref State s) {
	return cast(ubyte[])fn(s);
}

///
State fromBytes(alias fn)(ubyte[] data) {
	return fn(cast(string)data);
}

///
State restoreFromFile(Deserialize)(string filename)
		if (is(typeof(Deserialize([])) == State))
{
	import std.stdio : File;
	import std.file : getSize;

	auto buf = new ubyte[filename.getSize];
	auto inf = File(filename);
	inf.rawRead(buf);

	return Deserialize(buf);
}

unittest {
	import spdr.core.command, spdr.core.file;
	State s;
	auto args = depConst(["-l"]);
	auto exename = depConst("/usr/bin/ls");
	auto exe = new DepFile(exename);
	auto cmd = new DepCommand(depTuple(exe, args));

	cmd.resolve(s);

	persistToFile!(toBytes!(serializeToJson))(s, "testout.txt");
}
