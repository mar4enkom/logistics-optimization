using JuMP
using HiGHS

# Include the model building and plotting functions
include("main_model.jl")
include("plotting.jl")
include("results_utils.jl")

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

# --- Use the shared results printing function ---
print_supply_chain_results(model_ex2, nodes_ex, node_data_ex, configurable_nodes_ex, example_pk_ex, "Example 2")

# --- Plot results if optimal ---
if termination_status(model_ex2) == MOI.OPTIMAL
    plot_network_results(model_ex2, nodes_ex, arc_definitions_ex, node_data_ex, configurable_nodes_ex, example_pk_ex, "example2_network.png", "Example 2 Network")
else
    println("Skipping plot generation for Example 2 as the model was not solved optimally. Status: ", termination_status(model_ex2))
end

println("Finished Example 2.") 