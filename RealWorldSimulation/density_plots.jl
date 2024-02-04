
function density_from_data(
    x::AbstractVector,
    w::AbstractVector;
    bandwidth = 0.1,
    trim = false,
    )
    #
    @assert length(x) > 0
    @assert length(w) == length(x)
    # calculate cumulative distribution function
    p = sortperm(x)
    x = x[p]
    w = w[p]
    y = Vector{eltype(x)}()
    q = Vector{eltype(w)}()
    push!(y, x[begin])
    push!(q, w[begin])
    for k in 2:length(x)
        if x[k] == y[end]
            q[end] += w[k]
        else
            push!(y, x[k])
            push!(q, q[end] + w[k])
        end
    end
    q = q ./ q[end]
    # density calculation via finite differences
    if length(y) > 1
        delta = bandwidth * (y[end] - y[begin])
    else
        delta = bandwidth
    end
    # q_interp = linear_interpolation(y, q, extrapolation_bc = Flat())
    q_interp = extrapolate(interpolate(y, q, AkimaMonotonicInterpolation()), Flat())
    d(x_) = (q_interp(x_+0.5*delta) - q_interp(x_-0.5*delta)) / delta
    # we incorporate additional smoothing
    d_av(x_) = sum([ d(x_ + k*delta) for k in -0.5:0.01:0.5 ]) / 101.0
    #
    if trim
        start = y[begin]
        stop = y[end]
    else
        start = y[begin] - 0.5*delta
        stop = y[end] + 0.5*delta
    end
    #
    μ = (w' * x) / sum(w)
    ν = sqrt((w' * (x.*x))/ sum(w) - μ^2)
    #
    return (
        start = start,
        stop = stop,
        density = d_av,
        mean = μ,
        std = ν,
    )
end

function plot_density(
    x::AbstractVector;
    bandwidth = 0.1,
    trim = false,
    plot_size = (400, 400),
    xlabel = "x",
    font_size = 8,
    )
    # densities
    e = ones(length(x))
    d = density_from_data(x, e, bandwidth=bandwidth, trim=trim)
    step = (d.stop - d.start) / 200
    x_data = d.start:step:d.stop
    p = plot(
        x_data,
        d.density,
        label = @sprintf("μ=%.4f, ν=%.4f", d.mean, d.std),
        xlabel = xlabel,
        ylabel = "probability density",
        size = plot_size,
        xtickfontsize = font_size,
        ytickfontsize = font_size,
        xguidefontsize = font_size,
        yguidefontsize = font_size,
        legendfontsize = font_size,
        plot_titlefontsize = font_size,
        left_margin = 5Plots.mm,  # adjust this if xaxis label is cut off
        bottom_margin = 5Plots.mm,
    )
    return p
end

function plot_densities(
    x::AbstractVector,
    w::AbstractVector;
    bandwidth = 0.1,
    trim = false,
    plot_size = (800, 400),
    xlabel = "x",
    font_size = 8,
    )
    # densities
    e = ones(length(x))
    d = density_from_data(x, e, bandwidth=bandwidth, trim=trim)
    step = (d.stop - d.start) / 200
    x_data = d.start:step:d.stop
    p1 = plot(
        x_data,
        d.density,
        label = @sprintf("unweighted: μ=%.4f, ν=%.4f", d.mean, d.std),
        xlabel = xlabel,
        ylabel = "probability density",
        xtickfontsize = font_size,
        ytickfontsize = font_size,
        xguidefontsize = font_size,
        yguidefontsize = font_size,
        legendfontsize = font_size,
        plot_titlefontsize = font_size,
    )
    #
    d = density_from_data(x, w, bandwidth=bandwidth, trim=trim)
    step = (d.stop - d.start) / 200
    x_data = d.start:step:d.stop
    plot!(p1, x_data, d.density, label = @sprintf("weighted: μ=%.4f, ν=%.4f", d.mean, d.std))
    #
    p2 = plot(x, w, seriestype=:scatter, label="w(x)",
        xlabel = xlabel,
        ylabel = "Radon-Nikodym derivative",
        xtickfontsize = font_size,
        ytickfontsize = font_size,
        xguidefontsize = font_size,
        yguidefontsize = font_size,
        legendfontsize = font_size,
        plot_titlefontsize = font_size,
    )
    #
    p = plot(p1, p2,
      layout=(1,2),
      size = plot_size,
      left_margin = 5Plots.mm,  # adjust this if xaxis label is cut off
      bottom_margin = 5Plots.mm,
    )
    return p
end
