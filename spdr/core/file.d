module spdr.core.file;
import spdr.core.base;
import std.typecons;

///
struct File {
	/// Name of the file
	string filename;
	/// Whether the file exists
	bool exist;
}

/// Represents a file that can be used as dependency
final class DepFile : DepImpure!(File, string) {
protected:
	override Tuple!(Hash, File) nonrecursive_resolve(ref State s, string filename) {
		Hash tmp_hash;
		File result;
		result.filename = filename;
		s.fs.fetch(filename, tmp_hash, result.exist);
		return tuple(tmp_hash, result);
	}
	mixin DepCtor!(string);
}

/// Represent the file listing inside a directory
version(none) final class DepDirEntries : DepValue!(string[]) {
private:
	string[] result;
	DepValue!string path;
public:

}

unittest {
	import std.stdio : writeln;
	auto exename = depConst("/usr/bin/ls");
	auto exe = new DepFile(exename);
	State s;
	auto v = exe.resolve(s);
	writeln(v);
	writeln(exe.resolve(s));
}
