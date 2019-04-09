module spdr.builder.base;
import spdr.core.base;
import spdr.core.file;

/// Mixin template for Builders
mixin template BuilderBaseMixin() {
protected:
	this(string src, DepIndef!string o) {
		sourceDir = src;
		outputDir = o;
	}
public:
	typeof(this) cd(string dirname) {
		auto ret = new typeof(this)(sourceDir ~ dirname, outputDir ~ dirname.depConst);
		copyTo(ret);
		return ret;
	}

	void subdir(string dirname)() {
		mixin("import "~dirname~".spdr : spdr;");
		auto b = cd(dirname);
		spdr(b);
	}

	this(DepIndef!string o) {
		import std.file : getcwd;
		auto cwd = getcwd ~ "/";
		this(cwd, cwd.depConst ~ o);
	}

	this(BuilderBase o) {
		sourceDir = o.sourceDir;
		outputDir = o.outputDir;
	}
}

/// Base class for builders
abstract class BuilderBase {
public:
	string sourceDir;
	DepIndef!string outputDir;

	/// Get the path to a source file
	DepIndef!string srcFile(DepIndef!string filename) {
		return sourceDir.depConst ~ filename;
	}

	/// Get the path to an output file
	DepIndef!string outFile(DepIndef!string filename) {
		return outputDir ~ filename;
	}
}

unittest {
	final class BuilderTest : BuilderBase {
		mixin BuilderBaseMixin;
		void copyTo(BuilderTest) {}
	}
	auto b = new BuilderTest(".".depConst);
	b.subdir!"test";
}
