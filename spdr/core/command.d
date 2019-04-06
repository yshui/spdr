module spdr.core.command;
import spdr.core.base;
///
struct CommandResult
{
	///
	int exit_code;
}

/// Represents a command that need to be run
final class DepCommand : DepValue!CommandResult
{
private:
	CommandResult result;
	DepValue!(string[]) _command;

public:
	override void resolve(ref State s)
	{
		import std.digest.sha : SHA256, makeDigest;
		auto cmd = _command.get();
		auto sha = makeDigest!SHA256;
		foreach(a; cmd) {
			sha.put(cast(const(ubyte[]))a);
		}

		import std.process : spawnProcess, wait;
		auto pid = spawnProcess(cmd);
		result.exit_code = pid.wait;
		sha.put(cast(ubyte[])[result.exit_code]);
		set_hash(s, sha.finish());
	}

	///
	@property const(DepValue!(string[])) command() const
	{
		return _command;
	}
}
