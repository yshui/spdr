module spdr.core.command;
import spdr.core.base;
import spdr.core.file;
import std.typecons : Tuple;

///
struct CommandResult
{
	///
	int exit_code;
}

/// Represents a command that need to be run
final class DepCommand : Dep!(CommandResult, Tuple!(File, string[]))
{
protected:
	override CommandResult nonrecursive_resolve(ref State s, Tuple!(File, string[]) args)
	{
		auto exe = args[0].filename;
		auto cmd = args[1];
		CommandResult result;

		import std.process : spawnProcess, wait;

		auto pid = spawnProcess(exe ~ cmd);
		result.exit_code = pid.wait;
		return result;
	}

	final class DepCommandArgs : Dep!(string[], Tuple!(File, string[]))
	{
	protected:
		override string[] nonrecursive_resolve(ref State s, Tuple!(File, string[]) args)
		{
			return args[0].filename ~ args[1];
		}

		mixin DepCtor!(Tuple!(File, string[]));
	}

	///
	@property auto command_args()
	{
		return new DepCommandArgs(dep);
	}

	mixin DepCtor!(Tuple!(File, string[]));
}

unittest
{
	State s;
	{
		auto args = depConst(["-l"]);
		auto exename = depConst("/usr/bin/ls");
		auto exe = new DepFile(exename);
		auto cmd = new DepCommand(depTuple(exe, args));
		cmd.resolve(s);
		import std.stdio : writeln;

		writeln(cmd.name);
		writeln(s.ps);
	}

	// Construct same set of variables again
	auto args = depConst(["-l"]);
	auto exename = depConst("/usr/bin/ls");
	auto exe = new DepFile(exename);
	auto cmd = new DepCommand(depTuple(exe, args));

	// Test deserialization from persistent store
	cmd.resolve(s);
}
