using JuMP
using HiGHS

# Include the model building and plotting functions
include("main_model.jl")
include("plotting.jl")

println("Running Example 3: Extended Echelons and Scenarios")

# --- Define the network structure and parameters for Example 3 ---

nodes_ex3 = [
    "S1", "S2", "S3", "S4",                  # Suppliers
    "M1", "M2", "M3",                      # Manufacturers
    "WC1S", "WC1L", "WC2S", "WC2L",        # Central Warehouses (Small/Large)
    "WR1S", "WR1L", "WR2S", "WR2L", "WR3S", "WR3L", # Regional Warehouses (Small/Large)
    "C1", "C2", "C3", "C4"                   # Customers
]

arc_definitions_ex3 = [
    # Supplier -> Manufacturer
    Dict(:from => "S1", :to => "M1", :cost => 4.0), Dict(:from => "S1", :to => "M2", :cost => 4.5),
    Dict(:from => "S2", :to => "M1", :cost => 4.2), Dict(:from => "S2", :to => "M2", :cost => 4.7), Dict(:from => "S2", :to => "M3", :cost => 5.0),
    Dict(:from => "S3", :to => "M2", :cost => 5.1), Dict(:from => "S3", :to => "M3", :cost => 5.3),
    Dict(:from => "S4", :to => "M3", :cost => 4.8),

    # Manufacturer -> Central Warehouse
    Dict(:from => "M1", :to => "WC1S", :cost => 1.5), Dict(:from => "M1", :to => "WC1L", :cost => 1.5),
    Dict(:from => "M1", :to => "WC2S", :cost => 1.8), Dict(:from => "M1", :to => "WC2L", :cost => 1.8),
    Dict(:from => "M2", :to => "WC1S", :cost => 1.6), Dict(:from => "M2", :to => "WC1L", :cost => 1.6),
    Dict(:from => "M2", :to => "WC2S", :cost => 1.7), Dict(:from => "M2", :to => "WC2L", :cost => 1.7),
    Dict(:from => "M3", :to => "WC2S", :cost => 1.9), Dict(:from => "M3", :to => "WC2L", :cost => 1.9),


    # Central Warehouse -> Regional Warehouse
    Dict(:from => "WC1S", :to => "WR1S", :cost => 0.8), Dict(:from => "WC1S", :to => "WR1L", :cost => 0.8),
    Dict(:from => "WC1L", :to => "WR1S", :cost => 0.8), Dict(:from => "WC1L", :to => "WR1L", :cost => 0.8),
    Dict(:from => "WC1S", :to => "WR2S", :cost => 1.0), Dict(:from => "WC1S", :to => "WR2L", :cost => 1.0),
    Dict(:from => "WC1L", :to => "WR2S", :cost => 1.0), Dict(:from => "WC1L", :to => "WR2L", :cost => 1.0),

    Dict(:from => "WC2S", :to => "WR2S", :cost => 0.9), Dict(:from => "WC2S", :to => "WR2L", :cost => 0.9),
    Dict(:from => "WC2L", :to => "WR2S", :cost => 0.9), Dict(:from => "WC2L", :to => "WR2L", :cost => 0.9),
    Dict(:from => "WC2S", :to => "WR3S", :cost => 1.1), Dict(:from => "WC2S", :to => "WR3L", :cost => 1.1),
    Dict(:from => "WC2L", :to => "WR3S", :cost => 1.1), Dict(:from => "WC2L", :to => "WR3L", :cost => 1.1),

    # Regional Warehouse -> Customer
    Dict(:from => "WR1S", :to => "C1", :cost => 0.5), Dict(:from => "WR1L", :to => "C1", :cost => 0.5),
    Dict(:from => "WR1S", :to => "C2", :cost => 0.6), Dict(:from => "WR1L", :to => "C2", :cost => 0.6),

    Dict(:from => "WR2S", :to => "C2", :cost => 0.55), Dict(:from => "WR2L", :to => "C2", :cost => 0.55),
    Dict(:from => "WR2S", :to => "C3", :cost => 0.65), Dict(:from => "WR2L", :to => "C3", :cost => 0.65),

    Dict(:from => "WR3S", :to => "C3", :cost => 0.6), Dict(:from => "WR3L", :to => "C3", :cost => 0.6),
    Dict(:from => "WR3S", :to => "C4", :cost => 0.7), Dict(:from => "WR3L", :to => "C4", :cost => 0.7)
]

configurable_nodes_ex3 = [
    "S1", "S2", "S3", "S4",
    "WC1S", "WC1L", "WC2S", "WC2L",
    "WR1S", "WR1L", "WR2S", "WR2L", "WR3S", "WR3L"
]

node_data_ex3 = Dict(
    # Suppliers
    "S1" => Dict(:type => :source, :capacity => 700, :processing_cost => 0, :opening_cost => 25),
    "S2" => Dict(:type => :source, :capacity => 800, :processing_cost => 0, :opening_cost => 30),
    "S3" => Dict(:type => :source, :capacity => 750, :processing_cost => 0, :opening_cost => 28),
    "S4" => Dict(:type => :source, :capacity => 650, :processing_cost => 0, :opening_cost => 22),
    # Manufacturers
    "M1" => Dict(:type => :intermediate, :capacity => 1500, :processing_cost => 10),
    "M2" => Dict(:type => :intermediate, :capacity => 1800, :processing_cost => 12),
    "M3" => Dict(:type => :intermediate, :capacity => 1600, :processing_cost => 11),
    # Central Warehouses
    "WC1S" => Dict(:type => :intermediate, :capacity => 500, :processing_cost => 0, :opening_cost => 150),
    "WC1L" => Dict(:type => :intermediate, :capacity => 1000, :processing_cost => 0, :opening_cost => 250),
    "WC2S" => Dict(:type => :intermediate, :capacity => 600, :processing_cost => 0, :opening_cost => 180),
    "WC2L" => Dict(:type => :intermediate, :capacity => 1200, :processing_cost => 0, :opening_cost => 280),
    # Regional Warehouses
    "WR1S" => Dict(:type => :intermediate, :capacity => 300, :processing_cost => 0, :opening_cost => 80),
    "WR1L" => Dict(:type => :intermediate, :capacity => 600, :processing_cost => 0, :opening_cost => 130),
    "WR2S" => Dict(:type => :intermediate, :capacity => 350, :processing_cost => 0, :opening_cost => 90),
    "WR2L" => Dict(:type => :intermediate, :capacity => 700, :processing_cost => 0, :opening_cost => 140),
    "WR3S" => Dict(:type => :intermediate, :capacity => 400, :processing_cost => 0, :opening_cost => 100),
    "WR3L" => Dict(:type => :intermediate, :capacity => 800, :processing_cost => 0, :opening_cost => 150),
    # Customers
    "C1" => Dict(:type => :demand, :demand => 200, :lost_demand_penalty => 99999999),
    "C2" => Dict(:type => :demand, :demand => 250, :lost_demand_penalty => 99999999),
    "C3" => Dict(:type => :demand, :demand => 300, :lost_demand_penalty => 99999999),
    "C4" => Dict(:type => :demand, :demand => 150, :lost_demand_penalty => 99999999)
)

scenario_data_ex3 = Dict(
    :capacity_factor => Dict(
        # Scenario 1: Base case
        ("S1", 1)=>1.0, ("S2", 1)=>1.0, ("S3", 1)=>1.0, ("S4", 1)=>1.0,
        ("M1", 1)=>1.0, ("M2", 1)=>1.0, ("M3", 1)=>1.0,
        ("WC1S", 1)=>1.0, ("WC1L", 1)=>1.0, ("WC2S", 1)=>1.0, ("WC2L", 1)=>1.0,
        ("WR1S", 1)=>1.0, ("WR1L", 1)=>1.0, ("WR2S", 1)=>1.0, ("WR2L", 1)=>1.0, ("WR3S", 1)=>1.0, ("WR3L", 1)=>1.0,

        # Scenario 2: Supplier S1 and S2 disruption, WC1 fails
        ("S1", 2)=>0.5, ("S2", 2)=>0.7, ("S3", 2)=>1.0, ("S4", 2)=>1.0,
        ("M1", 2)=>1.0, ("M2", 2)=>1.0, ("M3", 2)=>1.0,
        ("WC1S", 2)=>0.0, ("WC1L", 2)=>0.0, ("WC2S", 2)=>1.0, ("WC2L", 2)=>1.0, # WC1 fails
        ("WR1S", 2)=>1.0, ("WR1L", 2)=>1.0, ("WR2S", 2)=>1.0, ("WR2L", 2)=>1.0, ("WR3S", 2)=>1.0, ("WR3L", 2)=>1.0,

        # Scenario 3: Manufacturer M2 capacity reduced, WR2 fails
        ("S1", 3)=>1.0, ("S2", 3)=>1.0, ("S3", 3)=>1.0, ("S4", 3)=>1.0,
        ("M1", 3)=>1.0, ("M2", 3)=>0.6, ("M3", 3)=>1.0, # M2 capacity reduced
        ("WC1S", 3)=>1.0, ("WC1L", 3)=>1.0, ("WC2S", 3)=>1.0, ("WC2L", 3)=>1.0,
        ("WR1S", 3)=>1.0, ("WR1L", 3)=>1.0, ("WR2S", 3)=>0.0, ("WR2L", 3)=>0.0, ("WR3S", 3)=>1.0, ("WR3L", 3)=>1.0, # WR2 fails

        # Scenario 4: General capacity reduction for some suppliers and warehouses
        ("S1", 4)=>0.8, ("S2", 4)=>1.0, ("S3", 4)=>0.7, ("S4", 4)=>1.0,
        ("M1", 4)=>1.0, ("M2", 4)=>1.0, ("M3", 4)=>1.0,
        ("WC1S", 4)=>0.9, ("WC1L", 4)=>0.9, ("WC2S", 4)=>1.0, ("WC2L", 4)=>1.0,
        ("WR1S", 4)=>1.0, ("WR1L", 4)=>1.0, ("WR2S", 4)=>0.8, ("WR2L", 4)=>0.8, ("WR3S", 4)=>1.0, ("WR3L", 4)=>1.0,
    ),
    :demand_factor => Dict(
        ("C1", 1)=>1.0, ("C2", 1)=>1.0, ("C3", 1)=>1.0, ("C4", 1)=>1.0,
        ("C1", 2)=>1.2, ("C2", 2)=>1.1, ("C3", 2)=>1.0, ("C4", 2)=>1.3, # Scenario 2: Demand increase
        ("C1", 3)=>0.9, ("C2", 3)=>0.8, ("C3", 3)=>1.1, ("C4", 3)=>0.9, # Scenario 3: Mixed demand changes
        ("C1", 4)=>1.1, ("C2", 4)=>1.0, ("C3", 4)=>1.2, ("C4", 4)=>0.8  # Scenario 4: Mixed demand changes
    )
)

example_pk_ex3 = Dict(1 => 0.4, 2 => 0.25, 3 => 0.20, 4 => 0.15) # Probabilities for 4 scenarios
revenue_per_unit_ex3 = 60

# Build the generalized model
model_ex3 = build_generalized_supply_chain_model(
    nodes_ex3,
    arc_definitions_ex3,
    node_data_ex3,
    scenario_data_ex3,
    configurable_nodes_ex3,
    example_pk_ex3,
    revenue_per_unit_ex3,
    HiGHS.Optimizer
)

# Add constraints specific to this example (DC size choice)
# Ensure only one size (or none) is chosen per DC location
@constraint(model_ex3, dc_size_select_wc1, model_ex3[:is_open]["WC1S"] + model_ex3[:is_open]["WC1L"] <= 1)
@constraint(model_ex3, dc_size_select_wc2, model_ex3[:is_open]["WC2S"] + model_ex3[:is_open]["WC2L"] <= 1)
@constraint(model_ex3, dc_size_select_wr1, model_ex3[:is_open]["WR1S"] + model_ex3[:is_open]["WR1L"] <= 1)
@constraint(model_ex3, dc_size_select_wr2, model_ex3[:is_open]["WR2S"] + model_ex3[:is_open]["WR2L"] <= 1)
@constraint(model_ex3, dc_size_select_wr3, model_ex3[:is_open]["WR3S"] + model_ex3[:is_open]["WR3L"] <= 1)


println("Optimizing Example 3...")
optimize!(model_ex3)

# --- Check results ---
if termination_status(model_ex3) == MOI.OPTIMAL
    println("Optimal solution found for Example 3.")
    println("Objective value: ", objective_value(model_ex3))

    println("Selected Configurable Nodes (is_open):")
    for n in configurable_nodes_ex3
        if value(model_ex3[:is_open][n]) > 0.5
            println("  Node ", n, " is selected/open.")
        end
    end

    println("
--- Second-Stage Variables for Example 3 (Non-Zero Flow & Lost Demand per Scenario) ---")
    nodes_in_flow_ex3 = union(first.(model_ex3.ext[:arcs]), last.(model_ex3.ext[:arcs]))
    K_scen_ex3 = keys(example_pk_ex3)
    for k in K_scen_ex3
        println("
  Scenario ", k, " (Probability: ", example_pk_ex3[k], ")")
        println("    Flow (source -> destination: value):")
        has_flow_in_scenario = false
        for i in nodes_in_flow_ex3, j in nodes_in_flow_ex3
             if (i, j) in model_ex3.ext[:arcs]
                 flow_val = value(model_ex3[:flow][i, j, k])
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
        demand_nodes_ex3 = filter(n -> node_data_ex3[n][:type] == :demand, nodes_ex3)
        has_lost_demand_in_scenario = false
        for n in demand_nodes_ex3
            if haskey(model_ex3[:lost_demand], (n, k)) # Check if variable exists for this combo
                ld_val = value(model_ex3[:lost_demand][n, k])
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
    plot_network_results(model_ex3, nodes_ex3, arc_definitions_ex3, node_data_ex3, configurable_nodes_ex3, example_pk_ex3, "example3_network.png")

else
    println("Solver status for Example 3: ", termination_status(model_ex3))
end

println("Finished Example 3.") 