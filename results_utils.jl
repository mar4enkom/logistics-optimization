using JuMP
using Printf

"""
Prints the results of a solved supply chain model.

Args:
    model (JuMP.Model): The solved JuMP model.
    nodes (Vector): List of all node identifiers.
    node_data (Dict): Dictionary containing data for each node (e.g., type, demand).
    configurable_nodes (Vector): List of node identifiers that are configurable (can be opened/closed).
    pk (Dict): Dictionary of scenario probabilities (scenario_id => probability).
    example_name (String): A name for the example, used in print statements (e.g., "Example 1").
"""
function print_supply_chain_results(
    model::JuMP.Model,
    nodes::Vector,
    node_data::Dict,
    configurable_nodes::Vector,
    pk::Dict,
    example_name::String
)
    println("\n--- Results for $(example_name) ---")

    if termination_status(model) == MOI.OPTIMAL
        println("Optimal solution found for $(example_name).")
        @printf "Objective value: %.2f\n" objective_value(model)

        println("\nSelected Configurable Nodes (is_open):")
        opened_nodes_count = 0
        for n in configurable_nodes
            if value(model[:is_open][n]) > 0.5
                println("  Node ", n, " is selected/open.")
                opened_nodes_count += 1
            end
        end
        if opened_nodes_count == 0
            println("  (No configurable nodes were selected/opened)")
        end

        println("\n--- Second-Stage Variables for $(example_name) (Non-Zero Flow & Lost Demand per Scenario) ---")
        
        # Ensure model.ext[:arcs] exists and is populated correctly by build_generalized_supply_chain_model
        if !isdefined(model, :ext) || !haskey(model.ext, :arcs)
             println("Error: model.ext[:arcs] not found. Cannot print flow details.")
             # Attempt to reconstruct arcs if possible, or provide guidance.
             # This part might be tricky if build_generalized_supply_chain_model structure is not available here.
             # For now, we'll rely on it being there.
        end

        nodes_in_flow = Set{String}()
        if isdefined(model, :ext) && haskey(model.ext, :arcs)
            for arc in model.ext[:arcs]
                push!(nodes_in_flow, String(arc[1]))
                push!(nodes_in_flow, String(arc[2]))
            end
        else # Fallback if model.ext[:arcs] is not available
            union_nodes = Set{String}()
            # This is a less ideal fallback: try to infer from flow variable keys if they exist
            if haskey(model, :flow)
                for (i,j,k) in keys(model[:flow].data)
                    push!(union_nodes, String(i))
                    push!(union_nodes, String(j))
                end
            end
            nodes_in_flow = union_nodes # May include nodes not in the original list if keys are tuples of Any
        end


        K_scen = keys(pk)
        for k in K_scen
            println("\n  Scenario ", k, " (Probability: ", pk[k], ")")
            println("    Flow (source -> destination: value):")
            has_flow_in_scenario = false
            # Iterate through all possible pairs of nodes present in the flow variables or arcs
            # This is more robust if model.ext[:arcs] is not perfectly aligned or available
            
            possible_flow_nodes = collect(nodes_in_flow) # Use the collected nodes

            for i_str in possible_flow_nodes
                for j_str in possible_flow_nodes
                    # Check if the flow variable exists for this arc and scenario
                    if haskey(model[:flow], (i_str, j_str, k))
                        flow_val = value(model[:flow][i_str, j_str, k])
                        if flow_val > 1e-6 # Print non-zero values
                            @printf "      %s -> %s: %.2f\n" i_str j_str flow_val
                            has_flow_in_scenario = true
                        end
                    # If model.ext[:arcs] is available, we can use it as the source of truth for valid arcs
                    # else if isdefined(model, :ext) && haskey(model.ext, :arcs) && (Symbol(i_str), Symbol(j_str)) in model.ext[:arcs]
                    #    # This case implies the variable should exist if the arc is defined,
                    #    # but the above haskey check is more direct for variable existence.
                    end
                end
            end

            if !has_flow_in_scenario
                println("      (No non-zero flow in this scenario)")
            end

            println("    Lost Demand:")
            # Ensure node_data keys are strings if nodes are strings
            demand_nodes = filter(n_any -> begin
                                            n = String(n_any) # Ensure string for dict lookup
                                            haskey(node_data, n) && node_data[n][:type] == :demand
                                        end, nodes)

            has_lost_demand_in_scenario = false
            for n_any in demand_nodes
                n = String(n_any) # Ensure string for dict lookup and variable key
                if haskey(model[:lost_demand], (n, k)) # Check if variable exists for this combo
                    ld_val = value(model[:lost_demand][n, k])
                    if ld_val > 1e-6
                        @printf "      Node %s: %.2f\n" n ld_val
                        has_lost_demand_in_scenario = true
                    end
                end
            end
            if !has_lost_demand_in_scenario
                println("      (No lost demand in this scenario)")
            end
        end
    else
        println("Solver status for $(example_name): ", termination_status(model))
    end
    println("\nFinished processing results for $(example_name).")
end 