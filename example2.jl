using JuMP
using HiGHS

# Include the model building and plotting functions
include("main_model.jl")
include("plotting.jl")

println("Running Example 2: Simple Network")

# --- Define the network structure and parameters for Example 2 ---
# This is the simpler S1, S2, R dataset

nodes_ex = ["S1", "S2", "R"]

arc_definitions_ex = [
    Dict(:from => "S1", :to => "R", :cost => 10),
    Dict(:from => "S2", :to => "R", :cost => 12), # Slightly different cost for S2->R
]

configurable_nodes_ex = ["S1", "S2"]

node_data_ex = Dict(
    "S1" => Dict(:type => :source, :capacity => 0, :processing_cost => 0, :opening_cost => 20),
    "S2" => Dict(:type => :source, :capacity => 600, :processing_cost => 0, :opening_cost => 10),
    "R"  => Dict(:type => :demand, :demand => 700, :lost_demand_penalty => 500) # Increased demand
)

scenario_data_ex = Dict(
    :capacity_factor => Dict(
        ("S1", 1) => 1.0, ("S2", 1) => 1.0, # Base scenario
        ("S1", 2) => 1.0, ("S2", 2) => 1.0, # S1 capacity reduced
        ("S1", 3) => 1.0, ("S2", 3) => 1.0, # S2 capacity reduced
    ),
    :demand_factor => Dict( # Demand is constant across scenarios for this simple example
        ("R", 1) => 1.0,
        ("R", 2) => 1.0,
        ("R", 3) => 1.0,
    )
)

example_pk_ex = Dict(1 => 0.7, 2 => 0.15, 3 => 0.15)
revenue_per_unit_ex = 50

# Build the generalized model
model_ex2 = build_generalized_supply_chain_model(
    nodes_ex,
    arc_definitions_ex,
    node_data_ex,
    scenario_data_ex,
    configurable_nodes_ex,
    example_pk_ex,
    revenue_per_unit_ex,
    HiGHS.Optimizer
)

# No specific additional constraints for this simple example

println("Optimizing Example 2...")
optimize!(model_ex2)

# --- Check results ---
if termination_status(model_ex2) == MOI.OPTIMAL
    println("Optimal solution found for Example 2.")
    println("Objective value: ", objective_value(model_ex2))

    println("Selected Configurable Nodes (is_open):")
    for n in configurable_nodes_ex
        if value(model_ex2[:is_open][n]) > 0.5
            println("  Node ", n, " is selected/open.")
        end
    end

    println("\n--- Second-Stage Variables for Example 2 (Non-Zero Flow & Lost Demand per Scenario) ---")
    nodes_in_flow_ex2 = union(first.(model_ex2.ext[:arcs]), last.(model_ex2.ext[:arcs]))
    K_scen_ex2 = keys(example_pk_ex)
    for k in K_scen_ex2
        println("\n  Scenario ", k, " (Probability: ", example_pk_ex[k], ")")
        println("    Flow (source -> destination: value):")
        has_flow_in_scenario = false
        for i in nodes_in_flow_ex2, j in nodes_in_flow_ex2
             if (i, j) in model_ex2.ext[:arcs]
                 flow_val = value(model_ex2[:flow][i, j, k])
                 if flow_val > 1e-6 # Print non-zero values
                     println("      ", i, " -> ", j, ": ", round(flow_val, digits=2))
                     has_flow_in_scenario = true
                 end
             end
        end
        if !has_flow_in_scenario
            println("      (No non-zero flow in this scenario)")
        end

        println("    Lost Demand:")
        demand_nodes_ex2 = filter(n -> node_data_ex[n][:type] == :demand, nodes_ex)
        has_lost_demand_in_scenario = false
        for n in demand_nodes_ex2
            if haskey(model_ex2[:lost_demand], (n,k)) # Check if variable exists for this combo
                ld_val = value(model_ex2[:lost_demand][n, k])
                if ld_val > 1e-6
                    println("      Node ", n, ": ", round(ld_val, digits=2))
                    has_lost_demand_in_scenario = true
                end
            end
        end
        if !has_lost_demand_in_scenario
            println("      (No lost demand in this scenario)")
        end
    end

    # Plot the results
    plot_network_results(model_ex2, nodes_ex, arc_definitions_ex, node_data_ex, configurable_nodes_ex, example_pk_ex, "example2_network.png")

else
    println("Solver status for Example 2: ", termination_status(model_ex2))
end

println("Finished Example 2.") 