module spdr.core.file;
import spdr.core.base;
import std.typecons;

///
struct File
{
	/// Name of the file
	string filename;
	/// Whether the file exists
	bool exist;
}

/// Represents a file that can be used as dependency
final class DepFile : DepImpure!(File, string)
{
protected:
	override @trusted Tuple!(Hash, File) nonrecursive_resolve(ref State s, string filename)
	{
		import std.file : exists;
		import std.digest : makeDigest;
		import std.digest.sha : SHA256;

		File result;
		result.exist = filename.exists;
		result.filename = filename;
		auto sha = makeDigest!SHA256;
		sha.put(cast(ubyte) result.exist);
		if (result.exist)
		{
			import std.stdio : ioFile = File;

			auto inf = ioFile(filename);
			foreach (ubyte[] buf; inf.byChunk(4096))
			{
				sha.put(buf);
			}
		}
		return tuple(sha.finish, result);
	}

	mixin DepCtor!(string);
}

/// Models an output file from some other dep vertex
final class DepOutputFile(D) : Dep!(File, Tuple!(D, string))
{
protected:
	override @trusted File nonrecursive_resolve(ref State s, D, string filename) {
		File result;
		result.exist = filename.exists;
		result.filename = filename;
		return File;
	}

	mixin DepCtor!(D, string);

}

/// Represent the file listing inside a directory
version (none) final class DepDirEntries : DepValue!(string[])
{
private:
	string[] result;
	DepValue!string path;
public:

}

unittest
{
	import std.stdio : writeln;

	auto exename = depConst("/usr/bin/ls");
	auto exe = new DepFile(exename);
	State s;
	auto v = exe.resolve(s);
	writeln(v);
	writeln(exe.resolve(s));
}
