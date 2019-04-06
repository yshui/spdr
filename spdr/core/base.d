module spdr.core.base;
import std.typecons;
import std.range.interfaces;
import std.digest.sha;
import std.digest : makeDigest;

///
struct State
{
	/// Used by the state to get rid of the const qualifier
	DepVertex[const(DepVertex)] self;
	/// The resolution queue
	const(DepVertex)[] queue;
	/// Queue vertex to be resolved
	void enqueue(const(DepVertex)[] d)
	{
		queue ~= d;
	}

	/// Add a new dependent of `dependency`. Intended to be used from `resolve` since it
	/// only have access to const(DepVertex) dependencies
	void add_dependent(const(DepVertex) dependency, DepVertex dependent) {
		auto unqdep = self[dependency];
		unqdep.reverse_dependencies ~= dependent;
		dependent.add_dependency(dependency);
	}
}

alias Hash = ubyte[32];

/// A vertex in a dependence graph
abstract class DepVertex
{
private:
	/// A list of vertices that depend on this vertex
	const(DepVertex)[] reverse_dependencies;
	/// A list of vertices this vertex depends on. Empty usually means
	/// this vertex has external dependencies
	const(DepVertex)[] dependencies;
	Hash _hash;
	/// An identifier for this vertex, if null, the content of this vertex won't be persisted
	/// **Has** to be unique
	string name;
	/// Whether this vertex is resolved
	bool _resolved = false;

protected:
	@property void set_hash()(ref State s, auto ref const(Hash) new_hash)
	{
		import std.algorithm.comparison : equal;

		if (new_hash != _hash)
		{
			s.enqueue(reverse_dependencies);
			_hash = new_hash;
		}
	}

public:

	///
	@property ref const(bool) resolved() const
	{
		return _resolved;
	}
	/// ditto
	@property void resolved(bool n)
	in(!_resolved || _resolved == n)do // Cannot mark resolved vertex unresolved
	{
		_resolved = n;
	}

	/// Resolve this vertex. Will only be called after all of this vertex's dependencies
	/// have be resolved
	abstract void resolve(ref State);
	/// Return hash value of this vertex. Hash value changes can be used to detect
	/// change of output of this vertex.
	Hash hash() const
	{
		return _hash;
	}

	///
	void add_dependent(const(DepVertex) v)
	{
		reverse_dependencies ~= v;
	}

	///
	void add_dependency(const(DepVertex) v)
	in(!resolved)do
	{
		dependencies ~= v;
	}
}

/// Can be used to group several vertices together
class DepGroup : DepVertex
{
public:
	override void resolve(ref State s)
	{
		// Calculate the output hash as the hash of all the dependencies' output hash
		auto sha256 = makeDigest!SHA256();
		foreach (v; dependencies)
		{
			sha256.put(v.hash[]);
		}
		set_hash(s, sha256.finish());
	}
}

/// A vertex whose resolution will yield value of type `T`
abstract class DepValue(T) : DepVertex
{
protected:
	abstract ref const(T) get_unchecked() const;
public:
	/// Get the result value
	final ref const(T) get() const
	in(resolved)do
	{
		return get_unchecked;
	}

	///
	auto opDispatch(string name)() const if (is(typeof(mixin("T.init." ~ name))))
	{
		ref auto get_member()
		{
			return mixin("get." ~ name);
		}

		auto dg = new DepDelegate!(typeof(mixin("T.init." ~ name)))(&get_member);
		dg.add_dependency(this);
		return dg;
	}
}

///
final class DepDelegate(T) : DepValue!T
{
private:
	alias Dg = ref const(T) delegate();
	Dg dg;
protected:
	override ref const(T) get_unchecked() const
	{
		return dg();
	}

public:

	override void resolve(ref State s)
	{
		// Calculate the output hash as the hash of all the dependencies' output hash
		auto sha256 = makeDigest!SHA256();
		foreach (v; dependencies)
		{
			sha256.put(v.hash[]);
		}
		set_hash(s, sha256.finish());
	}
	///
	this(Dg dg)
	{
		this.dg = dg;
	}
}

unittest
{
	///
	struct TestT1
	{
		int a, b;
	}
	///
	final class TestDepT1 : DepValue!TestT1
	{
	private:
		TestT1 r;
	protected:
		override ref const(TestT1) get_unchecked() const
		{
			return r;
		}

	public:

		override void resolve(ref State)
		{
		}

		this()
		{
			r = TestT1(1, 2);
			resolved = true;
		}
	}

	import std.stdio : writeln;

	auto x = new TestDepT1;
	assert(x.get == TestT1(1, 2));

	auto y = x.a;
	y.resolved = true; // mark as resolved for testing purpose
	pragma(msg, typeof(y));
	assert(y.get == 1);
}
