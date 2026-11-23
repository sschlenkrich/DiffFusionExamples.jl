
function extract_numbers(str_vec)
    float_vec = Float64[]
    for s in str_vec
        try
            x = parse(Float64, s)
            push!(float_vec, x)
        catch
            continue
        end
    end
    return float_vec
end


function smile(
    table::DataFrame,
    exercise_time::Float64,
    swap_time::Float64,
    )
    table_ = table[
        (table.exercise_time .== exercise_time) .&
        (table.swap_time .== swap_time), :
    ]
    if size(table_, 1) != 1
        error("No smile found.")
    end
    strikes = table_.forward .+ extract_numbers(names(table)) .* 1e-4
    volatilities = collect(table_[1, end-(length(strikes)-1):end])
    return (
        forward = table_.forward[1],
        atm_volatilities = table_[:, "0"][1],
        strikes = strikes,
        volatilities = volatilities,
    )
end



_VOL_COLORS = ( :blue, :red, :green, :orange )
_FWD_COLORS = ( :gold, :gold )

_SCALING = 1e+4

function plot_smiles(
    table::DataFrame,
    exercise_times::Vector{Float64},
    swap_time::Float64;
    show_label = true,
    show_title = true,
    table_compare::Union{DataFrame, Nothing} = nothing,
    )
    #
    fig = plot()
    forwards = Float64[]
    atm_vols = Float64[]
    forwards_compare = Float64[]
    atm_vols_compare = Float64[]
    for (idx, exercise_time) in enumerate(exercise_times)
        (forward, atm_vol, strikes, volatilities) = smile(table, exercise_time, swap_time)
        if show_label
            label = @sprintf("%.0fy-%.0fy", exercise_time, swap_time)
        else
            label = nothing
        end
        plot!(
            fig,
            strikes * _SCALING,
            volatilities * _SCALING,
            label = label,
            color = _VOL_COLORS[(idx % length(_VOL_COLORS)) + 1],
            marker = :circle,
            markersize = 2,
            linewidth = 1,
            linestyle = :dot,
        )
        push!(forwards, forward)
        push!(atm_vols, atm_vol)
        if !isnothing(table_compare)
            (forward, atm_vol, strikes, volatilities) = smile(table_compare, exercise_time, swap_time)
            plot!(
                fig,
                strikes * _SCALING,
                volatilities * _SCALING,
                label = nothing,
                color = _VOL_COLORS[(idx % length(_VOL_COLORS)) + 1],
                marker = :rect,
                markersize = 2,
                linewidth = 1,
                linestyle = :dot,
            )
            push!(forwards_compare, forward)
            push!(atm_vols_compare, atm_vol)
        end
    end
    if show_label
        label = "ATM"
    else
        label = nothing
    end
    plot!(
        fig,
        forwards * _SCALING,
        atm_vols * _SCALING,
        label = label,
        color = _FWD_COLORS[1],
        linestyle = :solid,
    )
    if !isnothing(table_compare)
        plot!(
            fig,
            forwards_compare * _SCALING,
            atm_vols_compare * _SCALING,
            label = nothing,
            color = _FWD_COLORS[2],
            linestyle = :solid,
        )
    end
    xlabel!(fig, "strike (bp)")
    ylabel!(fig, "normal volatility (bp)")
    if show_title
        title!(fig, @sprintf("%.0fy swap term", swap_time), titlefontsize = 10)
    end
    return fig
end


function plot_smiles(
    table::DataFrame,
    exercise_times::Vector{Float64},
    swap_times::Vector{Float64};
    show_label = true,
    show_title = true,
    size = (1200, 800), 
    table_compare::Union{DataFrame, Nothing} = nothing,
    )
    #
    figs = [
        plot_smiles(
            table,
            exercise_times,
            swap_time,
            show_label=show_label,
            show_title=show_title,
            table_compare = table_compare,
        )
        for swap_time in swap_times
    ]
    fig = plot(figs..., size=size, margin=12Plots.mm,)
    return fig
end

