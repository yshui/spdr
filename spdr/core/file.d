module spdr.core.file;
import spdr.core.base;

///
struct File {
	/// Whether the file exists
	bool exist;
}

/// Represents a file that can be used as dependency
final class DepFile : DepValue!File {
private:
	File result;
	DepValue!string file_name;
protected:
	override ref const(File) get_unchecked() const {
		return result;
	}
public:
	override void resolve(ref State s) {
		auto fname = file_name.get;
		import std.file : exists;
		import std.digest : makeDigest;
		import std.digest.sha : SHA256;
		result.exist = fname.exists;
		auto sha = makeDigest!SHA256;
		sha.put(cast(ubyte)result.exist);
		if (result.exist) {
			import std.stdio : File;
			import std.digest : makeDigest;
			import std.digest.sha : SHA256;
			auto inf = File(fname);
			foreach (ubyte[] buf; inf.byChunk(4096)) {
				sha.put(buf);
			}
		}
		set_hash(s, sha.finish());
	}

	///
	this(DepValue!string fn) {
		file_name = fn;
		fn.add_dependent(this);
		add_dependency(fn);
	}
}

/// Represent the file listing inside a directory
final class DepDirEntries : DepValue!(string[]) {
private:
	string[] result;
	DepValue!string path;
public:

}
