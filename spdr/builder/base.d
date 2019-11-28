module spdr.builder.base;
import spdr.core.base;
import spdr.core.file;

/// Mixin template for Builders
mixin template BuilderBaseMixin() {
protected:
	this(string src, TaskBase!string o) {
		sourceDir = src;
		outputDir = o;
	}
public:
	typeof(this) cd(string dirname) {
		auto ret = new typeof(this)(sourceDir ~ dirname, outputDir ~ dirname.toConstTask);
		copyTo(ret);
		return ret;
	}

	void subdir(string dirname)() {
		mixin("import "~dirname~".spdr : spdr;");
		auto b = cd(dirname);
		spdr(b);
	}

	this(TaskBase!string o) {
		import std.file : getcwd;
		auto cwd = getcwd ~ "/";
		this(cwd, cwd.toConstTask ~ o);
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
	TaskBase!string outputDir;

	/// Get the path to a source file
	TaskBase!string srcFile(TaskBase!string filename) {
		return sourceDir.toConstTask ~ filename;
	}

	/// Get the path to an output file
	TaskBase!string outFile(TaskBase!string filename) {
		return outputDir ~ filename;
	}
}

unittest {
	final class BuilderTest : BuilderBase {
		mixin BuilderBaseMixin;
		void copyTo(BuilderTest) {}
	}
	auto b = new BuilderTest(".".toConstTask);
	b.subdir!"test";
}
