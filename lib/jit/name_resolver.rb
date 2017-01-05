module NameResolver
  extend self

  def resolve_local_var(index, locals)
    locals[-(index-1)]
  end
end
