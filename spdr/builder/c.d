module spdr.builder.c;
import spdr.builder.base;
import spdr.core.base;

/// Builder for C projects
final class C : BuilderBase {
	mixin BuilderBaseMixin;
protected:
	/// Include directories, has to be absolute path
	DepIndef!string[] includeDirs;
	/// Library directories, has to be absolute path
	DepIndef!string[] libraryDirs;

	void copyTo(C other) {
		other.includeDirs = includeDirs;
		other.libraryDirs = libraryDirs;
	}
public:

}
