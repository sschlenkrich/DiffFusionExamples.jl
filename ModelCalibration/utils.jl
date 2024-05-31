

"""
    plot_volatility(
        std_table,
        currency,
        model_terms,
        model_values,
        scaling,
        )

Plot historical volatilities and model-implied volatlities.
"""
function plot_volatility(
    std_table,
    currency,
    model_terms,
    model_values,
    scaling,
    )
    #
    table = filter(:CURRENCY => ==(currency), std_table)
    table[!,"VOLATILITY"] = table[!,"VOLATILITY"] * scaling # in percent/bp
    #
    b = box(table, x=:YEARS, y=:VOLATILITY, name="historical volatility")
    #
    s = scatter(
        x = model_terms,
        y = model_values * scaling,
        mode = "markers",
        marker = attr(size=12, line=attr(width=2, color="DarkSlateGrey")),
        name="model-implied volatility",
    )
    #
    if scaling == 100.0
        scaling_unit = " (%)"
    elseif scaling == 10000.0
        scaling_unit = " (bp)"
    else
        scaling_unit = ""
    end
    layout = Layout(
        title= currency * " Volatility",
        xaxis_title="rate term",
        yaxis_title="volatility" * scaling_unit,
        legend_title="Output",
        font=attr(
            family="Arial",
            size=12,
            color="RebeccaPurple"
        )
    )
    return plot([b, s], layout)
end


"""
    iuppert(k::Integer,n::Integer)

Determine the upper triangular index pair `(i,j)` for
an `(n,n)` matrix a serial index `k`.

Method allows iterating the upper triangular indices
of a square matrix via

````
for (i,j) in (iuppert(k, n) for k in 1:Int(n*(n-1)/2))
    ...
end
```
See

https://discourse.julialang.org/t/iterating-over-elements-of-upper-triangular-matrix-but-cartesian-indices-are-needed/65498/3

"""
@inline function iuppert(k::Integer,n::Integer)
    i = n - 1 - floor(Int,sqrt(-8*k + 4*n*(n-1) + 1)/2 - 0.5)
    j = k + i + ( (n-i+1)*(n-i) - n*(n-1) )÷2
    return i, j
end


"""
    make_index_list(curr_and_year::AbstractVector{<:Tuple})

Take a list of tuples `(curr, year)` (of risk factors) and calculate 
an index list representing the upper triangular part of the
crrelation matrix.

This method is used to identify interest rate correlations.
"""
function make_index_list(curr_and_year::AbstractVector{<:Tuple})
    l = curr_and_year  # abbreviation
    n = length(curr_and_year)
    return [
        (l[idx[1]][1], l[idx[1]][2], l[idx[2]][1], l[idx[2]][2])
        for idx in (iuppert(k, n) for k in 1:Int(n*(n-1)/2))
    ]
end


"""
    make_index_list(curr_and_year_1::AbstractVector{<:Tuple}, curr_and_year_2::AbstractVector{<:Tuple})

Take two lists of tuples `(curr, year)` (of risk factors) and calculate 
an index list representing the rectangular correlation matrix for these
risk factors.

This method is used to identify rates versus rates and rates versus FX
correlations.
"""
function make_index_list(curr_and_year_1::AbstractVector{<:Tuple}, curr_and_year_2::AbstractVector{<:Tuple})
    l1 = curr_and_year_1  # abbreviation
    l2 = curr_and_year_2  # abbreviation
    return [
        (l1[1], l1[2], l2[1], l2[2])
        for l1 in curr_and_year_1 for l2 in curr_and_year_2
    ]
end



"""
    model_correlation(index_list, keys_and_terms, corr_matrix)

Identify relevant correlation values from an `index_list` in a
`corr_matrix` with labels `keys_and_terms`.

This method is used to select relevant model-implied correlations.
"""
function model_correlation(index_list, keys_and_terms, corr_matrix)
    return [
        corr_matrix[
            findall(x->x==(l[1],l[2]),keys_and_terms)[begin],
            findall(x->x==(l[3],l[4]),keys_and_terms)[begin]
        ]
        for l in index_list
    ]
end


"""
    make_sub_table(table, index_list)

Slice input correlation data table.
"""
function make_sub_table(table, index_list)
    t = table  # abbreviation
    l = index_list  # abbreviation
    tmp = vcat([
        [
            t[(t.CURRENCY1 .== l[1]) .&& (t.YEARS1 .== l[2]) .&& (t.CURRENCY2 .== l[3]) .&& (t.YEARS2 .== l[4]),:],
            t[(t.CURRENCY1 .== l[3]) .&& (t.YEARS1 .== l[4]) .&& (t.CURRENCY2 .== l[1]) .&& (t.YEARS2 .== l[2]),:],
        ]
        for l in index_list
    ]...)
    return vcat(tmp...)
end


"""
    plot_correlation(
    table,
    index_list,
    values,
    )

Plot historical correlations and model-implied correlations.
"""
function plot_correlation(
    table,
    index_list,
    values,
    )
    #
    t = make_sub_table(table, index_list)
    t[!, "XLABEL"] = t[!, "CURRENCY1"] .* "_" .* string.(t[!, "YEARS1"]) .* "__" .* t[!, "CURRENCY2"] .* "_" .* string.(t[!, "YEARS2"])
    t[!, "CORRELATION"] = t[!, "value"] .* 100  # in percent
    b = box(t, x=:XLABEL, y=:CORRELATION, name="historical correlation")
    #
    xlabels = [
        t[1] * "_" * string.(t[2]) * "__" * t[3] * "_" .* string(t[4])
        for t in index_list
    ]
    yvalues = values .* 100 # in percent
    s = scatter(
        x = xlabels,
        y = yvalues,
        mode = "markers",
        marker = attr(size=12, line=attr(width=2, color="DarkSlateGrey")),
        name="model-implied correlation",
    )
    #
    layout = Layout(
        title= "Correlation",
        xaxis_title="risk factors",
        yaxis_title="correlation (%)",
        legend_title="Output",
        font=attr(
            family="Arial",
            size=12,
            color="RebeccaPurple"
        )
    )
    return plot([b, s], layout)
end


"""
    rates_model(model_params)

Generate `Context`, `GaussianHjmModel` and `CorrelationHolder`
for a 3-factor rates interest rate model for EUR.
"""
function rates_model(model_params)
    #
    ch = DiffFusion.correlation_holder("Std", "<>", typeof(model_params[("EUR_f_1","EUR_f_2")]))
    for t in model_params
        if t[1][2] != ""
            DiffFusion.set_correlation!(ch, t[1][1], t[1][2], t[2])
        end
    end
    #
    t0 = [ 0.0 ]
    d = model_params  # abbreviation
    #
    delta = [ d[("delta_1","")], d[("delta_2","")], d[("delta_3","")] ]
    chi = [ d[("chi_1","")], d[("chi_2","")], d[("chi_3","")] ]
    #
    hjm_eur = DiffFusion.gaussian_hjm_model(
        "EUR",
        DiffFusion.flat_parameter(delta),
        DiffFusion.flat_parameter(chi),
        DiffFusion.backward_flat_volatility("",t0, [ d[("EUR_f_1","")] d[("EUR_f_2","")] d[("EUR_f_3","")] ]' ),  # sigma
        ch,
        nothing,
        DiffFusion.ZeroRateScaling,
    )
    #
    ctx = DiffFusion.Context("Std",
        DiffFusion.NumeraireEntry("EUR", "EUR", Dict()),
        Dict{String, DiffFusion.RatesEntry}([
            ("EUR", DiffFusion.RatesEntry("EUR","EUR", Dict())),
        ]),
        Dict{String, DiffFusion.AssetEntry}(),
        Dict{String, DiffFusion.ForwardIndexEntry}(),
        Dict{String, DiffFusion.FutureIndexEntry}(),
        Dict{String, DiffFusion.FixingEntry}(),
    )
    #
    return (ctx, hjm_eur, ch)
end


"""
    hybrid_model(model_params)

Generate `Context`, `SimpleModel` and `CorrelationHolder`
for a hybrid G3 model (EUR-USD-GBP) with 3-factor rates
models. 
"""
function hybrid_model(model_params)
    #
    ch = DiffFusion.correlation_holder("Std")
    for t in model_params
        if t[1][2] != ""
            DiffFusion.set_correlation!(ch, t[1][1], t[1][2], t[2])
        end
    end
    #
    t0 = [ 0.0 ]
    d = model_params  # abbreviation
    #
    delta = [ d[("delta_1","")], d[("delta_2","")], d[("delta_3","")] ]
    #
    hjm_eur = DiffFusion.gaussian_hjm_model(
        "EUR",
        DiffFusion.flat_parameter(delta),
        DiffFusion.flat_parameter([ d[("EUR_chi_1","")], d[("EUR_chi_2","")], d[("EUR_chi_3","")] ]),
        DiffFusion.backward_flat_volatility("",t0, [ d[("EUR_f_1","")] d[("EUR_f_2","")] d[("EUR_f_3","")] ]' ),  # sigma
        ch,
        nothing,
        DiffFusion.ZeroRateScaling,
    )
    fx_usd_eur = DiffFusion.lognormal_asset_model(
        "USD-EUR",
        DiffFusion.flat_volatility("", d[("USD-EUR_x","")]),
        ch,
        nothing,
    )
    hjm_usd = DiffFusion.gaussian_hjm_model(
        "USD",
        DiffFusion.flat_parameter(delta),
        DiffFusion.flat_parameter([ d[("USD_chi_1","")], d[("USD_chi_2","")], d[("USD_chi_3","")] ]),
        DiffFusion.backward_flat_volatility("",t0, [ d[("USD_f_1","")] d[("USD_f_2","")] d[("USD_f_3","")] ]' ),  # sigma
        ch,
        fx_usd_eur,
        DiffFusion.ZeroRateScaling,
    )
    fx_gbp_eur = DiffFusion.lognormal_asset_model(
        "GBP-EUR",
        DiffFusion.flat_volatility("", d[("GBP-EUR_x","")]),
        ch,
        nothing,
    )
    hjm_gbp = DiffFusion.gaussian_hjm_model(
        "GBP",
        DiffFusion.flat_parameter(delta),
        DiffFusion.flat_parameter([ d[("GBP_chi_1","")], d[("GBP_chi_2","")], d[("GBP_chi_3","")] ]),
        DiffFusion.backward_flat_volatility("",t0, [ d[("GBP_f_1","")] d[("GBP_f_2","")] d[("GBP_f_3","")] ]' ),  # sigma
        ch,
        fx_gbp_eur,
        DiffFusion.ZeroRateScaling,
    )
    #
    models = [ hjm_eur, fx_usd_eur, hjm_usd, fx_gbp_eur, hjm_gbp ]
    mdl = DiffFusion.simple_model("Std", models)
    #
    ctx = DiffFusion.Context("Std",
        DiffFusion.NumeraireEntry("EUR", "EUR", Dict()),
        Dict{String, DiffFusion.RatesEntry}([
            ("EUR", DiffFusion.RatesEntry("EUR","EUR", Dict())),
            ("USD", DiffFusion.RatesEntry("USD", "USD", Dict())),
            ("GBP", DiffFusion.RatesEntry("GBP", "GBP", Dict())),
        ]),
        Dict{String, DiffFusion.AssetEntry}([
            ("USD-EUR", DiffFusion.AssetEntry("USD-EUR", "USD-EUR", "EUR", "USD", "pa/USD-EUR", Dict(), Dict())),
            ("GBP-EUR", DiffFusion.AssetEntry("GBP-EUR", "GBP-EUR", "EUR", "GBP", "pa/GBP-EUR", Dict(), Dict())),
        ]),
        Dict{String, DiffFusion.ForwardIndexEntry}(),
        Dict{String, DiffFusion.FutureIndexEntry}(),
        Dict{String, DiffFusion.FixingEntry}(),
    )
    #
    return (ctx, mdl, ch)
end


"""
    update_plots!(
    param_list, # ::AbstractArray{<:Tuple},
    model_params,
    std_table,
    corr_table;
    plot_vols = false,
    plot_rates_corrs = false,
    plot_fx_corrs = false,
    plot_fx_rates_corrs = false,
    plot_rates_rates_corrs = false,
    )

Generate plots of historical and model-implied volatilities
and correlations.

This method is used in the notebook.
"""
function update_rates_plots!(
    param_list, # ::AbstractArray{<:Tuple},
    model_params,
    std_table,
    corr_table;
    plot_vols = false,
    plot_rates_corrs = false,
    )
    #
    for t in param_list
        model_params[(t[1], t[2])] = t[3]
    end
    #
    (ctx, mdl, ch) = rates_model(model_params)
    keys_and_terms = [
        ("EUR", 1),
        ("EUR", 2),
        ("EUR", 5),
        ("EUR", 10),
        ("EUR", 20),
    ]
    (v, C) = DiffFusion.reference_rate_volatility_and_correlation(keys_and_terms, ctx, mdl, ch, 0.0, 1.0/12.0)
    #
    model_terms = [1.0, 2.0, 5.0, 10.0, 20.0]
    v_eur = v[1:5]
    #
    if plot_vols
        display("text/markdown", "## Volatilities:")
        display(plot_volatility(std_table, "EUR", model_terms, v_eur, 1.0e+4))
    end
    #
    rf_eur = [ ("EUR", 1), ("EUR", 2), ("EUR", 5), ("EUR", 10), ("EUR", 20),]
    #
    if plot_rates_corrs
        display("text/markdown", "## Rates Correlations:")
        idx = make_index_list(rf_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
    end
end


"""
    update_hybrid_plots!(
        param_list, # ::AbstractArray{<:Tuple},
        model_params,
        std_table,
        corr_table;
        plot_vols = false,
        plot_rates_corrs = false,
        plot_fx_corrs = false,
        plot_fx_rates_corrs = false,
        plot_rates_rates_corrs = false,
        )

Generate plots of historical and model-implied volatilities
and correlations.

This method is used in the notebook.
"""
function update_hybrid_plots!(
    param_list, # ::AbstractArray{<:Tuple},
    model_params,
    std_table,
    corr_table;
    plot_vols = false,
    plot_rates_corrs = false,
    plot_fx_corrs = false,
    plot_fx_rates_corrs = false,
    plot_rates_rates_corrs = false,
    )
    #
    for t in param_list
        model_params[(t[1], t[2])] = t[3]
    end
    #
    (ctx, mdl, ch) = hybrid_model(model_params)
    keys_and_terms = [
        ("EUR", 1),
        ("EUR", 2),
        ("EUR", 5),
        ("EUR", 10),
        ("EUR", 20),
        #
        ("USD", 1),
        ("USD", 2),
        ("USD", 5),
        ("USD", 10),
        ("USD", 20),
        #
        ("GBP", 1),
        ("GBP", 2),
        ("GBP", 5),
        ("GBP", 10),
        ("GBP", 20),
        #
        ("USD-EUR", 0),
        ("GBP-EUR", 0),
    ]
    (v, C) = DiffFusion.reference_rate_volatility_and_correlation(keys_and_terms, ctx, mdl, ch, 0.0, 1.0/12.0)
    #
    model_terms = [1.0, 2.0, 5.0, 10.0, 20.0]
    v_eur = v[1:5]
    v_usd = v[6:10]
    v_gbp = v[11:15]
    v_usd_eur = v[16:16]
    v_gbp_eur = v[17:17];
    #
    if plot_vols
        display("text/markdown", "## Volatilities:")
        display(plot_volatility(std_table, "EUR", model_terms, v_eur, 1.0e+4))
        display(plot_volatility(std_table, "USD", model_terms, v_usd, 1.0e+4))
        display(plot_volatility(std_table, "GBP", model_terms, v_gbp, 1.0e+4))
        display(plot_volatility(std_table, "USD-EUR", [0.0], v_usd_eur, 1.0e+2))
        display(plot_volatility(std_table, "GBP-EUR", [0.0], v_gbp_eur, 1.0e+2))
    end
    #
    rf_eur = [ ("EUR", 1), ("EUR", 2), ("EUR", 5), ("EUR", 10), ("EUR", 20),]
    rf_usd = [ ("USD", 1), ("USD", 2), ("USD", 5), ("USD", 10), ("USD", 20),]
    rf_gbp = [ ("GBP", 1), ("GBP", 2), ("GBP", 5), ("GBP", 10), ("GBP", 20),]
    rf_usd_eur = [ ("USD-EUR", 0),]
    rf_gbp_eur = [ ("GBP-EUR", 0),];
    #
    if plot_rates_corrs
        display("text/markdown", "## Rates Correlations:")
        idx = make_index_list(rf_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        idx = make_index_list(rf_usd)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        idx = make_index_list(rf_gbp)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        end
    #
    if plot_fx_corrs
        display("text/markdown", "## FX Correlations:")
        idx = make_index_list(rf_gbp_eur, rf_usd_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
    end
    #
    if plot_fx_rates_corrs
        display("text/markdown", "## FX versus Rates Correlations:")
        idx = make_index_list(rf_eur, rf_gbp_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        idx = make_index_list(rf_gbp, rf_gbp_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        idx = make_index_list(rf_gbp_eur, rf_usd)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        idx = make_index_list(rf_eur, rf_usd_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
        idx = make_index_list(rf_usd, rf_usd_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))    
        idx = make_index_list(rf_gbp, rf_usd_eur)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
    end
    #
    if plot_rates_rates_corrs
        display("text/markdown", "## Rates versus Rates Correlations:")
        idx = make_index_list(rf_eur, rf_usd)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))    
        idx = make_index_list(rf_eur, rf_gbp)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))    
        idx = make_index_list(rf_gbp, rf_usd)
        display(plot_correlation(corr_table, idx, model_correlation(idx, keys_and_terms, C)))
    end
end



"""
    rates_model_outputs(X::AbstractVector)

Specify a vector-valued function Y = F(X) that takes as input a float vector
and calculates as output a float vector.

Input are model parameter values, output are model-implied reference rate
volatilities and correlations.

This method is used to calculate model parameter sensitivities via AD.
"""
function rates_model_outputs(X::AbstractVector)
    @assert length(X) == 12
    model_params = Dict([
        (("delta_1", ""), X[1]),
        (("delta_2", ""), X[2]),
        (("delta_3", ""), X[3]),
        #
        (("chi_1", ""), X[4]),
        (("chi_2", ""), X[5]),
        (("chi_3", ""), X[6]),
        #
        (("EUR_f_1", ""), X[7]),
        (("EUR_f_2", ""), X[8]),
        (("EUR_f_3", ""), X[9]),
        #
        (("EUR_f_1", "EUR_f_2"), X[10]),
        (("EUR_f_2", "EUR_f_3"), X[11]),
        (("EUR_f_1", "EUR_f_3"), X[12]),
    ])
    #
    (ctx, mdl, ch) = rates_model(model_params)
    keys_and_terms = [
        ("EUR", 1),
        ("EUR", 2),
        ("EUR", 5),
        ("EUR", 10),
        ("EUR", 20),
    ]
    (v, C) = DiffFusion.reference_rate_volatility_and_correlation(keys_and_terms, ctx, mdl, ch, 0.0, 1.0/12.0)
    #
    v_eur = v[1:5]
    rf_eur = [ ("EUR", 1), ("EUR", 2), ("EUR", 5), ("EUR", 10), ("EUR", 20),]
    #
    idx = make_index_list(rf_eur)
    c_eur = model_correlation(idx, keys_and_terms, C)
    return vcat( v_eur, c_eur )
end


"""
    plot_model_sensitivities(model_params)

Calculate model parameter sensitivities via ForwardDiff AD and
create a structured heatmap plot to visualise sensitivities.
"""
function plot_model_sensitivities(model_params)
    #
    X = [
        model_params[("delta_1", "")],
        model_params[("delta_2", "")],
        model_params[("delta_3", "")],
        #
        model_params[("chi_1", "")],
        model_params[("chi_2", "")],
        model_params[("chi_3", "")],
        #
        model_params[("EUR_f_1", "")],
        model_params[("EUR_f_2", "")],
        model_params[("EUR_f_3", "")],
        #
        model_params[("EUR_f_1", "EUR_f_2")],
        model_params[("EUR_f_2", "EUR_f_3")],
        model_params[("EUR_f_1", "EUR_f_3")],
    ]
    #
    J = ForwardDiff.jacobian(rates_model_outputs, X)
    display("text/markdown", "## Jacobian Matrix:")
    show(stdout, "text/plain", round.(J, digits=4))
    #
    x_labels = [
        "delta_1",
        "delta_2",
        "delta_3",
        #
        "chi_1",
        "chi_2",
        "chi_3",
        #
        "EUR_f_1",
        "EUR_f_2",
        "EUR_f_3",
        #
        "EUR_f_1__EUR_f_2",
        "EUR_f_2__EUR_f_3",
        "EUR_f_1__EUR_f_3",
    ]
    #
    rf_eur = [ ("EUR", 1), ("EUR", 2), ("EUR", 5), ("EUR", 10), ("EUR", 20),]
    y_labels_vol = [
        l[1] * "_" * string(l[2])
        for l in rf_eur
    ]
    idx = make_index_list(rf_eur)
    y_labels_corr = [
        l[1] * "_" * string(l[2]) * "__" * l[3] * "_" * string(l[4])
        for l in idx
    ]
    y_labels = vcat(y_labels_vol, y_labels_corr)
    #
    x1 = x_labels[1:3]
    x2 = x_labels[4:6]
    x3 = x_labels[7:9]
    x4 = x_labels[10:12]
    #
    y1 = y_labels[1:5]
    y2 = y_labels[6:15]
    #
    J11 = J[1:5,1:3]  * 1e+4    # bp / y
    J21 = J[6:15,1:3] * 1e+2    # %  / y
    J12 = J[1:5,4:6]  * 1e+2    # bp / %
    J22 = J[6:15,4:6]           # %  / %
    J13 = J[1:5,7:9]            # bp / bp
    J23 = J[6:15,7:9] * 1e-2    # %  / bp
    J14 = J[1:5,10:12] * 1e+2   # bp / %
    J24 = J[6:15,10:12]         # % / %
    #
    c_scale = "YlOrRd"
    #
    hm11 = heatmap(x=x1, y=y1, z=J11, showscale=false, colorscale=c_scale,)
    hm21 = heatmap(x=x1, y=y2, z=J21, showscale=false, colorscale=c_scale,)
    #
    hm12 = heatmap(x=x2, y=y1, z=J12, showscale=false, colorscale=c_scale,)
    hm22 = heatmap(x=x2, y=y2, z=J22, showscale=false, colorscale=c_scale,)
    #
    hm13 = heatmap(x=x3, y=y1, z=J13, showscale=false, colorscale=c_scale,)
    hm23 = heatmap(x=x3, y=y2, z=J23, showscale=false, colorscale=c_scale,)
    #
    hm14 = heatmap(x=x4, y=y1, z=J14, showscale=false, colorscale=c_scale,)
    hm24 = heatmap(x=x4, y=y2, z=J24, showscale=false, colorscale=c_scale,)
    #
    as_text(x) = string(round(x, digits=2))
    t_font(x, r, q=0.5) = begin
        ratio = (x - minimum(r)) / (maximum(r) - minimum(r))
        if ratio < q
            return attr(color = "white")
        else
            return attr(color = "black")
        end
    end
    #
    ann11 = [
        attr(y=i-1, x=j-1, text=as_text(J11[i,j]), xref="x1", yref="y1", showarrow=false, font = t_font(J11[i,j], J11,),)
        for i in 1:size(J11, 1) for j in 1:size(J11, 2)
    ]
    ann12 = [
        attr(y=i-1, x=j-1, text=as_text(J12[i,j]), xref="x2", yref="y2", showarrow=false, font = t_font(J12[i,j], J12,),)
        for i in 1:size(J12, 1) for j in 1:size(J12, 2)
    ]
    ann13 = [
        attr(y=i-1, x=j-1, text=as_text(J13[i,j]), xref="x3", yref="y3", showarrow=false, font = t_font(J13[i,j], J13,),)
        for i in 1:size(J13, 1) for j in 1:size(J13, 2)
    ]
    ann14 = [
        attr(y=i-1, x=j-1, text=as_text(J14[i,j]), xref="x4", yref="y4", showarrow=false, font = t_font(J14[i,j], J14,),)
        for i in 1:size(J14, 1) for j in 1:size(J14, 2)
    ]
    ann21 = [
        attr(y=i-1, x=j-1, text=as_text(J21[i,j]),  xref="x5", yref="y5", showarrow=false, font = t_font(J21[i,j], J21,),)
        for i in 1:size(J21, 1) for j in 1:size(J21, 2)
    ]
    ann22 = [
        attr(y=i-1, x=j-1, text=as_text(J22[i,j]),  xref="x6", yref="y6", showarrow=false, font = t_font(J22[i,j], J22,),)
        for i in 1:size(J22, 1) for j in 1:size(J22, 2)
    ]
    ann23 = [
        attr(y=i-1, x=j-1, text=as_text(J23[i,j]),  xref="x7", yref="y7", showarrow=false, font = t_font(J23[i,j], J23,),)
        for i in 1:size(J23, 1) for j in 1:size(J23, 2)
    ]
    ann24 = [
        attr(y=i-1, x=j-1, text=as_text(J24[i,j]),  xref="x8", yref="y8", showarrow=false, font = t_font(J24[i,j], J24,),)
        for i in 1:size(J24, 1) for j in 1:size(J24, 2)
    ]
    #
    annotations = vcat(ann11, ann12, ann13, ann14, ann21, ann22, ann23, ann24,)
    #
    sp_titles = reshape([
        "bp / y",
        "bp / %",
        "bp / bp",
        "bp / %",
        #
        "% / y",
        "% / %",
        "% / bp",
        "% / %",
        ], (2,4)
    )
    #
    p = make_subplots(
        rows=2,
        cols=4,
        subplot_titles = sp_titles,
        vertical_spacing = 0.15,
        horizontal_spacing = 0.15,
    )
    #
    add_trace!(p, hm11, row=1, col=1)
    add_trace!(p, hm21, row=2, col=1)
    add_trace!(p, hm12, row=1, col=2)
    add_trace!(p, hm22, row=2, col=2)
    add_trace!(p, hm13, row=1, col=3)
    add_trace!(p, hm23, row=2, col=3)
    add_trace!(p, hm14, row=1, col=4)
    add_trace!(p, hm24, row=2, col=4)
    #
    relayout!(p,
        height = 800,
        width = 1200,
        title = "Refrence Rate Sensitivities: Volatility (top) and Correlations (bottom)",
        yaxis_autorange = "reversed",
        yaxis2_autorange = "reversed",
        yaxis3_autorange = "reversed",
        yaxis4_autorange = "reversed",
        yaxis5_autorange = "reversed",
        yaxis6_autorange = "reversed",
        yaxis7_autorange = "reversed",
        yaxis8_autorange = "reversed",
    )
    append!(p.plot.layout.annotations, annotations)
    #
    display(p)
end