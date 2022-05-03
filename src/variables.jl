struct VariableUnit end
struct VariableConnectType end
struct VariableNoiseType end
struct VariableDescriptionType end
struct VariableInput end
struct VariableOutput end
Symbolics.option_to_metadata_type(::Val{:unit}) = VariableUnit
Symbolics.option_to_metadata_type(::Val{:connect}) = VariableConnectType
Symbolics.option_to_metadata_type(::Val{:noise}) = VariableNoiseType
Symbolics.option_to_metadata_type(::Val{:description}) = VariableDescriptionType
Symbolics.option_to_metadata_type(::Val{:input}) = VariableInput
Symbolics.option_to_metadata_type(::Val{:output}) = VariableOutput

abstract type AbstractConnectType end
struct Equality <: AbstractConnectType end # Equality connection
struct Flow <: AbstractConnectType end     # sum to 0
struct Stream <: AbstractConnectType end   # special stream connector

function isvarkind(m, x)
    p = getparent(x, nothing)
    p === nothing || (x = p)
    getmetadata(x, m, false)
end

isinput(x) = isvarkind(VariableInput, x)
isoutput(x) = isvarkind(VariableOutput, x)

"""
$(SIGNATURES)

Takes a list of pairs of `variables=>values` and an ordered list of variables
and creates the array of values in the correct order with default values when
applicable.
"""
function varmap_to_vars(varmap, varlist; defaults=Dict(), check=true, toterm=Symbolics.diff2term, promotetoconcrete=nothing, tofloat=true, use_union=false)
    varlist = map(unwrap, varlist)
    # Edge cases where one of the arguments is effectively empty.
    is_incomplete_initialization = varmap isa DiffEqBase.NullParameters || varmap === nothing
    if is_incomplete_initialization || isempty(varmap)
        if isempty(defaults)
            if !is_incomplete_initialization && check
                isempty(varlist) || throw_missingvars(varlist)
            end
            return nothing
        else
            varmap = Dict()
        end
    end

    T = typeof(varmap)
    # We respect the input type
    container_type = T <: Dict ? Array : T

    vals = if eltype(varmap) <: Pair # `varmap` is a dict or an array of pairs
        varmap = todict(varmap)
        _varmap_to_vars(varmap, varlist; defaults=defaults, check=check, toterm=toterm)
    else # plain array-like initialization
        varmap
    end

    promotetoconcrete === nothing && (promotetoconcrete = container_type <: AbstractArray)
    if promotetoconcrete
        vals = promote_to_concrete(vals; tofloat=tofloat, use_union=use_union)
    end

    if isempty(vals)
        return nothing
    elseif container_type <: Tuple
        (vals...,)
    else
        SymbolicUtils.Code.create_array(container_type, eltype(vals), Val{1}(), Val(length(vals)), vals...)
    end
end

function _varmap_to_vars(varmap::Dict, varlist; defaults=Dict(), check=false, toterm=Symbolics.diff2term)
    varmap = merge(defaults, varmap) # prefers the `varmap`
    varmap = Dict(toterm(value(k))=>value(varmap[k]) for k in keys(varmap))
    # resolve symbolic parameter expressions
    for (p, v) in pairs(varmap)
        varmap[p] = fixpoint_sub(v, varmap)
    end

    missingvars = setdiff(varlist, keys(varmap))
    check && (isempty(missingvars) || throw_missingvars(missingvars))

    out = [varmap[var] for var in varlist]
end

@noinline throw_missingvars(vars) = throw(ArgumentError("$vars are missing from the variable map."))

struct IsHistory end
ishistory(x) = ishistory(unwrap(x))
ishistory(x::Symbolic) = getmetadata(x, IsHistory, false)
hist(x, t) = wrap(hist(unwrap(x), t))
hist(x::Symbolic, t) = setmetadata(toparam(similarterm(x, operation(x), [unwrap(t)], metadata=metadata(x))), IsHistory, true)
