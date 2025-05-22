using JuMP
using HiGHS

# Include the model building and plotting functions
include("main_model.jl")
include("plotting.jl")
include("results_utils.jl") # Added results utility

println("Running Example 1: Complex Network")

# --- Define the network structure and parameters for Example 1 ---
# This is the larger, more complex dataset

nodes_ex = ["S1", "S2", "S3", "M1", "M2", "W1S", "W1L", "W2S", "W2L", "C1", "C2"]

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

configurable_nodes_ex = ["S1", "S2", "S3", "W1S", "W1L", "W2S", "W2L"]

node_data_ex = Dict(
    "S1" => Dict(:type => :source, :capacity => 500, :processing_cost => 0, :opening_cost => 20), # Added opening_cost for S1,S2,S3
    "S2" => Dict(:type => :source, :capacity => 600, :processing_cost => 0, :opening_cost => 25),
    "S3" => Dict(:type => :source, :capacity => 550, :processing_cost => 0, :opening_cost => 30),
    "M1" => Dict(:type => :intermediate, :capacity => 1000, :processing_cost => 10),
    "M2" => Dict(:type => :intermediate, :capacity => 1200, :processing_cost => 12),
    "W1S" => Dict(:type => :intermediate, :capacity => 200, :processing_cost => 0, :opening_cost => 100),
    "W1L" => Dict(:type => :intermediate, :capacity => 400, :processing_cost => 0, :opening_cost => 150),
    "W2S" => Dict(:type => :intermediate, :capacity => 250, :processing_cost => 0, :opening_cost => 120),
    "W2L" => Dict(:type => :intermediate, :capacity => 450, :processing_cost => 0, :opening_cost => 180),
    "C1" => Dict(:type => :demand, :demand => 150, :lost_demand_penalty => 99999999),
    "C2" => Dict(:type => :demand, :demand => 200, :lost_demand_penalty => 99999999)
)

scenario_data_ex = Dict(
    :capacity_factor => Dict(
        ("S1", 1)=>1.0, ("S2", 1)=>1.0, ("S3", 1)=>1.0,
        ("S1", 2)=>0.8, ("S2", 2)=>0.9, ("S3", 2)=>1.0, # Scenario 2: S1, S2 capacity reduced
        ("S1", 3)=>1.0, ("S2", 3)=>1.0, ("S3", 3)=>0.7, # Scenario 3: S3 capacity reduced
        ("M1", 1)=>1.0, ("M2", 1)=>1.0,
        ("M1", 2)=>1.0, ("M2", 2)=>1.0,
        ("M1", 3)=>1.0, ("M2", 3)=>1.0,
        ("W1S", 1)=>1.0, ("W1L", 1)=>1.0, ("W2S", 1)=>1.0, ("W2L", 1)=>1.0,
        ("W1S", 2)=>0.0, ("W1L", 2)=>0.0, ("W2S", 2)=>1.0, ("W2L", 2)=>1.0, # Scenario 2: W1 (both S and L) fails
        ("W1S", 3)=>1.0, ("W1L", 3)=>1.0, ("W2S", 3)=>1.0, ("W2L", 3)=>1.0,
    ),
    :demand_factor => Dict(
        ("C1", 1)=>1.0, ("C2", 1)=>1.0,
        ("C1", 2)=>1.2, ("C2", 2)=>1.1, # Scenario 2: Demand increases
        ("C1", 3)=>0.9, ("C2", 3)=>0.8  # Scenario 3: Demand decreases
    )
)

example_pk_ex = Dict(1 => 0.6, 2 => 0.25, 3 => 0.15) # Adjusted probabilities
revenue_per_unit_ex = 50

# Build the generalized model
model_ex1 = build_generalized_supply_chain_model(
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
@constraint(model_ex1, dc_size_select_w1, model_ex1[:is_open]["W1S"] + model_ex1[:is_open]["W1L"] <= 1)
@constraint(model_ex1, dc_size_select_w2, model_ex1[:is_open]["W2S"] + model_ex1[:is_open]["W2L"] <= 1)


println("Optimizing Example 1...")
optimize!(model_ex1)

# --- Use the shared results printing function ---
print_supply_chain_results(model_ex1, nodes_ex, node_data_ex, configurable_nodes_ex, example_pk_ex, "Example 1")

# --- Plot results if optimal ---
if termination_status(model_ex1) == MOI.OPTIMAL
    plot_network_results(model_ex1, nodes_ex, arc_definitions_ex, node_data_ex, configurable_nodes_ex, example_pk_ex, "example1_network.png", "Example 1 Network")
else
    println("Skipping plot generation for Example 1 as the model was not solved optimally. Status: ", termination_status(model_ex1))
end

println("Finished Example 1.") 