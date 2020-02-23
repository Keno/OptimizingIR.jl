
struct Native <: AbstractMachine
end

compile(::Type{Native}, program::Program) = func(program)

# Based on Mike's IRTools.jl
function func(ir::Program)
    @eval @generated function $(gensym())($([v.symbol for v in input_variables(ir)]...))
        return build_function_body_expr($ir)
    end
end

tmpsym(i::Integer) = Symbol(:t, i)

function build_function_body_expr(ir::BasicBlock)
    block = Expr(:block)

    itr = eachinstruction(ir)
    for (i, instruction) in enumerate(itr)
        push!(block.args, Expr(:(=), tmpsym(i), julia_expr(ir, instruction)))
    end

    push!(block.args, return_expr(ir))

    return block
end

function return_expr(bb::BasicBlock)
    out_vars = output_variables(bb)

    if isempty(out_vars)
        return :(return nothing)
    elseif length(out_vars) == 1
        return :(return $(julia_expr(bb, out_vars[1])))
    else
        ret_tuple = Expr(:tuple)

        for v in out_vars
            push!(ret_tuple.args, julia_expr(bb, v))
        end

        return Expr(:return, ret_tuple)
    end
end

julia_expr(bb::BasicBlock, c::CallUnary) = Expr(:call, c.op, julia_expr(bb, c.arg))

function julia_expr(bb::BasicBlock, c::CallBinary)
    Expr(:call, c.op, julia_expr(bb, c.arg1), julia_expr(bb, c.arg2))
end

function julia_expr(bb::BasicBlock, c::CallVararg)
    Expr(:call, c.op, map( arg -> julia_expr(bb, arg), c.args)...)
end

julia_expr(bb::BasicBlock, c::ImpureInstruction) = julia_expr(bb, c.call)
julia_expr(bb::BasicBlock, c::PureInstruction) = julia_expr(bb, c.call)

julia_expr(bb::BasicBlock, constant::Const) = constant.val
julia_expr(bb::BasicBlock, ssa::SSAValue) = tmpsym(ssa.address)

function julia_expr(bb::BasicBlock, variable::Variable)
    if is_input(bb, variable)
        return variable.symbol
    else
        return julia_expr(bb, follow(bb, variable))
    end
end

function julia_expr(bb::BasicBlock, op::GetIndex)
    Expr(:call,
        Base.getindex,
        julia_expr(bb, op.array),
        map(i -> julia_expr(bb, i), op.index)...)
end

function julia_expr(bb::BasicBlock, op::SetIndex)
    Expr(:call,
        Base.setindex!,
        julia_expr(bb, op.array),
        julia_expr(bb, op.value),
        map(i -> julia_expr(bb, i), op.index)...)
end
