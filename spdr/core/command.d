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

final class CommandArgs : TaskBase!(string[])
{
protected:
	string[] value_;
public:
	override void resolve()
	{
		value_ = dep.value.value[0].filename ~ dep.value.value[1].dup;
	}

	override ref const(Hash) hash() const in (resolved) {
		return dep.value.hash;
	}

	override inout(string[]) value() inout in (resolved) {
		return value_;
	}

	mixin DependentTaskMixin!(Tuple!(File, string[]));
}

/// Represents a command that need to be run
final class Command : TaskBase!CommandResult
{
protected:
	CommandResult value_;
public:
	override void resolve()
	{
		auto exe = dep.value.value[0].filename;
		auto cmd = dep.value.value[1];
		CommandResult result;

		import std.process : spawnProcess, wait;

		auto pid = spawnProcess(exe ~ cmd);
		result.exit_code = pid.wait;
		resolved_ = true;
	}

	override inout(CommandResult) value() inout in (resolved) {
		return value_;
	}

	override ref const(Hash) hash() const in (resolved) {
		return dep.hash;
	}

	///
	@property auto command_args()
	{
		return new CommandArgs(dep);
	}

	mixin DependentTaskMixin!(Tuple!(File, string[]));
}

unittest
{
	{
		import spdr.core.base : recursivelyResolve;
		auto args = ["-l"].toConstTask;
		auto exename = "/usr/bin/ls".toConstTask;
		auto exe = new ExternalFile(exename);
		auto cmd = new Command(taskJoin(exe, args));

		cmd.recursivelyResolve;
		import std.stdio : writeln;

		writeln(cmd.name);
	}

	// Construct same set of variables again
	// TODO

	// Test deserialization from persistent store
}
