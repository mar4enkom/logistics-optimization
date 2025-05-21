using JuMP
using HiGHS # Example solver

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
    @constraint(model, flow_balance[n in nodes, k in K; node_data[n][:type] == :intermediate],
        # Inflow
        sum(flow[i, n, k] for i in nodes if (i, n) in A)
        ==
        # Outflow
        sum(flow[n, j, k] for j in nodes if (n, j) in A)
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
    @constraint(model, node_capacity[n in nodes, k in K; haskey(node_data[n], :capacity)],
        sum(flow[n, j, k] for j in nodes if (n, j) in A)
        <=
        node_data[n][:capacity] *
        get(scenario_data[:capacity_factor], (n, k), 1.0) *
        (n in configurable_nodes ? is_open[n] : 1.0) # Multiply by is_open only if configurable
    )

    return model
end


# --- Example Usage ---

# Define the network structure and parameters for the generalized model
# This example mimics the structure of the previous specific model

# Let's proceed with the separate nodes approach for DCs in the example data.

nodes_ex = ["S1", "S2", "S3", "M1", "M2", "W1S", "W1L", "W2S", "W2L", "C1", "C2"] # S=Small, L=Large

# Define network structure as a simple array of connections
arc_definitions_ex = [
    # Supplier -> Manufacturer connections
    Dict(:from => "S1", :to => "M1", :cost => 5.0),
    Dict(:from => "S1", :to => "M2", :cost => 5.5),
    Dict(:from => "S2", :to => "M1", :cost => 6.0),
    Dict(:from => "S2", :to => "M2", :cost => 6.5),
    Dict(:from => "S3", :to => "M1", :cost => 7.0),
    Dict(:from => "S3", :to => "M2", :cost => 7.5),

    # Manufacturer -> Warehouse connections
    Dict(:from => "M1", :to => "W1S", :cost => 2.0),
    Dict(:from => "M1", :to => "W1L", :cost => 2.0),
    Dict(:from => "M1", :to => "W2S", :cost => 2.5),
    Dict(:from => "M1", :to => "W2L", :cost => 2.5),
    Dict(:from => "M2", :to => "W1S", :cost => 2.2),
    Dict(:from => "M2", :to => "W1L", :cost => 2.2),
    Dict(:from => "M2", :to => "W2S", :cost => 2.7),
    Dict(:from => "M2", :to => "W2L", :cost => 2.7),

    # Warehouse -> Customer connections
    Dict(:from => "W1S", :to => "C1", :cost => 1.0),
    Dict(:from => "W1S", :to => "C2", :cost => 1.2),
    Dict(:from => "W1L", :to => "C1", :cost => 1.0),
    Dict(:from => "W1L", :to => "C2", :cost => 1.2),
    Dict(:from => "W2S", :to => "C1", :cost => 1.3),
    Dict(:from => "W2S", :to => "C2", :cost => 1.1),
    Dict(:from => "W2L", :to => "C1", :cost => 1.3),
    Dict(:from => "W2L", :to => "C2", :cost => 1.1)
]

configurable_nodes_ex = ["S1", "S2", "S3", "W1S", "W1L", "W2S", "W2L"] # Suppliers and DC options

node_data_ex = Dict(
    "S1" => Dict(:type => :source, :capacity => 500, :processing_cost => 0),
    "S2" => Dict(:type => :source, :capacity => 600, :processing_cost => 0),
    "S3" => Dict(:type => :source, :capacity => 550, :processing_cost => 0),
    "M1" => Dict(:type => :intermediate, :capacity => 1000, :processing_cost => 10), # pcm[1]
    "M2" => Dict(:type => :intermediate, :capacity => 1200, :processing_cost => 12), # pcm[2]
    "W1S" => Dict(:type => :intermediate, :capacity => 200, :processing_cost => 0, :opening_cost => 100), # caplw[small,1], flw[small,1]
    "W1L" => Dict(:type => :intermediate, :capacity => 400, :processing_cost => 0, :opening_cost => 150), # caplw[large,1], flw[large,1]
    "W2S" => Dict(:type => :intermediate, :capacity => 250, :processing_cost => 0, :opening_cost => 120), # caplw[small,2], flw[small,2]
    "W2L" => Dict(:type => :intermediate, :capacity => 450, :processing_cost => 0, :opening_cost => 180), # caplw[large,2], flw[large,2]
    "C1" => Dict(:type => :demand, :demand => 150, :lost_demand_penalty => 99999999), # dc[1], lsc[1]
    "C2" => Dict(:type => :demand, :demand => 200, :lost_demand_penalty => 99999999)  # dc[2], lsc[2]
)

scenario_data_ex = Dict(
    :capacity_factor => Dict(
        # Alpha (Suppliers)
        ("S1", 1)=>1, ("S2", 1)=>1, ("S3", 1)=>1,
        ("S1", 2)=>1, ("S2", 2)=>1, ("S3", 2)=>1,
        ("S1", 3)=>1, ("S2", 3)=>1, ("S3", 3)=>1,
        # Beta (Manufacturers)
        ("M1", 1)=>1, ("M2", 1)=>1,
        ("M1", 2)=>1, ("M2", 2)=>1,
        ("M1", 3)=>1, ("M2", 3)=>1,
        # Delta (Warehouses - affects all options at a location)
        ("W1S", 1)=>1, ("W1L", 1)=>1, ("W2S", 1)=>1, ("W2L", 1)=>1,
        ("W1S", 2)=>1, ("W1L", 2)=>1, ("W2S", 2)=>1, ("W2L", 2)=>1, # W1 fails
        ("W1S", 3)=>1, ("W1L", 3)=>1, ("W2S", 3)=>1, ("W2L", 3)=>1,
    ),
    :demand_factor => Dict() # Demand constant
)

example_pk_ex = Dict(1 => 0.7, 2 => 0.2, 3 => 0.1)
revenue_per_unit_ex = 50

# nodes_ex = ["S1", "S2", "R"]

# arc_definitions_ex = [
#     Dict(:from => "S1", :to => "R", :cost => 10),
#     Dict(:from => "S2", :to => "R", :cost => 10),
# ]

# configurable_nodes_ex = ["S1", "S2"] # Suppliers and DC options

# node_data_ex = Dict(
#     "S1" => Dict(:type => :source, :capacity => 500, :processing_cost => 0, :opening_cost => 20),
#     "S2" => Dict(:type => :source, :capacity => 600, :processing_cost => 0, :opening_cost => 10),
#     "R" => Dict(:type => :demand, :demand => 1, :lost_demand_penalty => 500)
# )

# scenario_data_ex = Dict(
#     :capacity_factor => Dict(
#         ("S1", 1)=>1, ("S2", 1)=>1,
#         ("S1", 2)=>1, ("S2", 2)=>1,
#         ("S1", 3)=>1, ("S2", 3)=>1,
#     ),
#     :demand_factor => Dict()
# )

# example_pk_ex = Dict(1 => 0.7, 2 => 0.2, 3 => 0.1)
# revenue_per_unit_ex = 50

# Build the generalized model
model_gen = build_generalized_supply_chain_model(
    nodes_ex,
    arc_definitions_ex,
    node_data_ex,
    scenario_data_ex,
    configurable_nodes_ex,
    example_pk_ex,
    revenue_per_unit_ex,
    HiGHS.Optimizer
)

# Add constraints specific to this example (DC size choice)
# Ensure only one size (or none) is chosen per DC location
# @constraint(model_gen, dc_size_select_w1, model_gen[:is_open]["W1S"] + model_gen[:is_open]["W1L"] <= 1)
# @constraint(model_gen, dc_size_select_w2, model_gen[:is_open]["W2S"] + model_gen[:is_open]["W2L"] <= 1)

# Add minimum flow constraint (original constraint 3)?
# QSM[s, m, k] >= msm * alpha[s, k] * y[s]
# Translates to: flow[s, m, k] >= msm * capacity_factor[s, k] * is_open[s] for s in S, m in M
# msm_val = 10 # Original msm value
# S_nodes = ["S1", "S2", "S3"]
# M_nodes = ["M1", "M2"]
# K_scen = [1, 2, 3]
# @constraint(model_gen, min_supplier_flow[s in S_nodes, m in M_nodes, k in K_scen; (s,m) in model_gen.ext[:arcs]],
#     model_gen[:flow][s, m, k] >= msm_val * get(scenario_data_ex[:capacity_factor], (s, k), 1.0) * model_gen[:is_open][s]
# )


# Print the model structure (optional)
# print(model_gen)

# Solve the model
optimize!(model_gen)

# --- Check results ---
if termination_status(model_gen) == MOI.OPTIMAL
    println("Optimal solution found.")
    println("Objective value: ", objective_value(model_gen))

    println("Selected Configurable Nodes (is_open):")
    for n in configurable_nodes_ex
        if value(model_gen[:is_open][n]) > 0.5
            println("  Node ", n, " is selected/open.")
        end
    end

    println("\n--- Second-Stage Variables (Non-Zero Flow per Scenario) ---")
    nodes_in_flow = union(first.(model_gen.ext[:arcs]), last.(model_gen.ext[:arcs]))
    K_scen = keys(example_pk_ex) # Re-define K_scen for the results printing section
    for k in K_scen
        println("\n  Scenario ", k, " (Probability: ", example_pk_ex[k], ")")
        println("    Flow (source -> destination: value):")
        for i in nodes_in_flow, j in nodes_in_flow
             if (i, j) in model_gen.ext[:arcs]
                 flow_val = value(model_gen[:flow][i, j, k])
                 if flow_val > 1e-6 # Print non-zero values
                     println("      ", i, " -> ", j, ": ", round(flow_val, digits=2))
                 end
             end
        end

        println("    Lost Demand:")
        demand_nodes = filter(n -> node_data_ex[n][:type] == :demand, nodes_ex)
        for n in demand_nodes
            ld_val = value(model_gen[:lost_demand][n, k])
            if ld_val > 1e-6
                println("      Node ", n, ": ", round(ld_val, digits=2))
            end

        end
    end

else
    println("Solver status: ", termination_status(model_gen))
end

# println("Model built successfully.")


# TODO: 1. check impact of each param -> Done via scenarios, can analyze sensitivity
#       2. try to plot and visualize some processes -> Requires plotting library (e.g., Graphs.jl, Plots.jl)
#       3. generalize model: develop possibility to add custom echelons -> Done with generic nodes/arcs
#       4. develop custom directions between nodes of echelons -> Done with directed arcs
#       5. supplier can satisfy only a piece of manufactory demand -> Handled by capacity constraints
#       6. add delivery time -> Would require adding time periods, making it dynamic/multi-period model (significant change) 