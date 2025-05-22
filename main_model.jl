using JuMP
using HiGHS # Example solver, make sure it's in the Project.toml of the examples

"""
Builds a generalized two-stage stochastic supply chain network design model.

Args:
    nodes (Vector): A list/vector of node identifiers.
    arc_definitions (Vector{Dict{Symbol, Any}}): A list of dictionaries, each defining an arc with its properties like :from, :to, and :cost.
    node_data (Dict{Any, Dict{Symbol, Any}}): Dictionary mapping node ID to its properties.
        Properties: :type (:source, :intermediate, :demand), :capacity, :processing_cost,
                    :opening_cost (optional, for configurable nodes), :demand, :lost_demand_penalty.
    scenario_data (Dict{Symbol, Dict{Tuple{Any, Any}, Real}}): Dictionary mapping scenario parameter type (:capacity_factor, :demand_factor)
                                                             to a dictionary mapping (node/demand_node, scenario_k) to its multiplier/value.
    configurable_nodes (Vector): List of node IDs that require an opening decision (first-stage).
    pk (Dict{Any, Real}): Dictionary mapping scenario ID k to its probability.
    revenue_per_unit (Real): Revenue generated per unit of demand satisfied.
    optimizer_factory (Any): An optional optimizer factory. Default: nothing.

Returns:
    JuMP.Model: The constructed JuMP model.
"""
function build_generalized_supply_chain_model(
    nodes,
    arc_definitions,
    node_data,
    scenario_data,
    configurable_nodes,
    pk,
    revenue_per_unit,
    optimizer_factory=nothing
)
    # Process arc_definitions to create arcs and arc_data
    arcs = Tuple{Any, Any}[] # (NodeName, NodeName)
    arc_data = Dict{Tuple{Any, Any}, Dict{Symbol, Any}}()
    for arc_def in arc_definitions
        push!(arcs, (arc_def[:from], arc_def[:to]))
        arc_data[(arc_def[:from], arc_def[:to])] = Dict(:transport_cost => arc_def[:cost])
    end

    K = keys(pk) # Set of scenarios
    A = arcs     # Set of allowed arcs

    # Create the model
    if optimizer_factory !== nothing
        model = Model(optimizer_factory)
    else
        model = Model() # No solver attached
    end

    # Store arcs in model extension data for access outside the function if needed
    model.ext[:arcs] = A

    # --- Decision Variables ---

    # First-stage: Node selection (if applicable)
    @variable(model, is_open[n in configurable_nodes], Bin)

    # Second-stage: Flow and lost demand
    @variable(model, flow[i in nodes, j in nodes, k in K; (i, j) in A] >= 0)
    @variable(model, lost_demand[n in nodes, k in K; node_data[n][:type] == :demand] >= 0)

    # --- Objective Function ---
    # Maximize Expected Profit = Expected (Revenue - Transport - Processing - LostDemandPenalty) - OpeningCosts

    @objective(model, Max,
        # --- First Stage Costs ---
        -sum(node_data[n][:opening_cost] * is_open[n] for n in configurable_nodes if haskey(node_data[n], :opening_cost)) +

        # --- Second Stage Expected Value ---
        sum(pk[k] * (
            # Revenue from satisfied demand
            revenue_per_unit * sum(
                (node_data[n][:demand] * get(scenario_data[:demand_factor], (n, k), 1.0)) - lost_demand[n, k]
                for n in nodes if node_data[n][:type] == :demand
            )
            # Transport Costs
            - sum(arc_data[(i, j)][:transport_cost] * flow[i, j, k] for (i, j) in A)
            # Processing Costs (cost per unit flowing *out* of the node)
            - sum(node_data[n][:processing_cost] * sum(flow[n, j, k] for j in nodes if (n, j) in A)
                  for n in nodes if haskey(node_data[n], :processing_cost) && node_data[n][:processing_cost] > 0)
            # Lost Demand Penalty
            - sum(node_data[n][:lost_demand_penalty] * lost_demand[n, k]
                  for n in nodes if node_data[n][:type] == :demand)
        ) for k in K)
    )

    # --- Constraints ---

    # Flow Balance Constraints (for intermediate and source nodes)
    @constraint(model, flow_balance[n in nodes, k in K; node_data[n][:type] == :intermediate || node_data[n][:type] == :source],
        # Inflow
        sum(flow[i, n, k] for i in nodes if (i, n) in A) +
        (node_data[n][:type] == :source ? # For source nodes, consider total potential "production" as inflow
            (haskey(node_data[n],:capacity) ? # if it has capacity, it's an implicit production limit
                node_data[n][:capacity] * get(scenario_data[:capacity_factor], (n,k), 1.0) * (n in configurable_nodes ? is_open[n] : 1.0)
                : Inf) # If source has no capacity, assume infinite potential *before* outflow constraint
            : 0 ) # Not a source node
        ==
        # Outflow
        sum(flow[n, j, k] for j in nodes if (n, j) in A) +
        (node_data[n][:type] == :source ? # For source nodes, outflow equals production
             (haskey(node_data[n],:capacity) ?
                node_data[n][:capacity] * get(scenario_data[:capacity_factor], (n,k), 1.0) * (n in configurable_nodes ? is_open[n] : 1.0)
                : Inf) - sum(flow[n,j,k] for j in nodes if (n,j) in A) # This term makes it sum to capacity if capacity is defined
            : 0) # Not a source node, this part is zero
    )


    # Demand Satisfaction Constraints (for demand nodes)
    @constraint(model, demand_satisfaction[n in nodes, k in K; node_data[n][:type] == :demand],
        # Inflow
        sum(flow[i, n, k] for i in nodes if (i, n) in A) + lost_demand[n, k]
        ==
        # Demand (adjusted for scenario)
        node_data[n][:demand] * get(scenario_data[:demand_factor], (n, k), 1.0)
    )

    # Node Capacity Constraints (total outflow <= capacity * scenario_factor * is_open_factor)
    # This applies to source and intermediate nodes that have a capacity defined.
    @constraint(model, node_capacity[n in nodes, k in K; haskey(node_data[n], :capacity) && (node_data[n][:type] == :source || node_data[n][:type] == :intermediate)],
        sum(flow[n, j, k] for j in nodes if (n, j) in A)
        <=
        node_data[n][:capacity] *
        get(scenario_data[:capacity_factor], (n, k), 1.0) *
        (n in configurable_nodes ? is_open[n] : 1.0) # Multiply by is_open only if configurable
    )

    return model
end 