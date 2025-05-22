using JuMP
using Graphs
using GraphMakie
using CairoMakie
using GeometryBasics # For Point2f
using Colors         # For RGBA

# Helper function to extract the leading alphabetic prefix from a node name
function get_node_prefix(node_name_str::String)
    match_val = match(r"^[A-Za-z]+", node_name_str)
    if match_val === nothing
        return "UNKNOWN" # Default for nodes without a clear alphabetic prefix
    end
    return uppercase(match_val.match)
end

"""
Generates and saves a plot of the supply chain network based on model results.

Args:
    model_gen (JuMP.Model): The solved JuMP model.
    nodes_ex (Vector): List of node identifiers used in the model.
    arc_definitions_ex (Vector{Dict{Symbol, Any}}): Arc definitions used.
    node_data_ex (Dict): Node data used.
    configurable_nodes_ex (Vector): List of configurable node IDs.
    pk_ex (Dict): Scenario probabilities used.
    output_filename (String): Filename for the saved plot (e.g., "network_plot.png").
"""
function plot_network_results(
    model_gen,
    nodes_ex,
    arc_definitions_ex,
    node_data_ex,
    configurable_nodes_ex,
    pk_ex,
    output_filename = "supply_chain_network.png"
)
    if termination_status(model_gen) == MOI.OPTIMAL
        try
            println("\nAttempting to generate plot: $(output_filename)")

            node_to_id = Dict(name => i for (i, name) in enumerate(nodes_ex))
            id_to_node = Dict(i => name for (name, i) in node_to_id)

            num_nodes = length(nodes_ex)
            g = SimpleDiGraph(num_nodes)

            for arc_def in arc_definitions_ex
                # Ensure node names are strings for prefix extraction if they aren't already
                from_node_str = String(arc_def[:from])
                to_node_str = String(arc_def[:to])
                if haskey(node_to_id, from_node_str) && haskey(node_to_id, to_node_str)
                    u = node_to_id[from_node_str]
                    v = node_to_id[to_node_str]
                    add_edge!(g, u, v)
                else
                    println("Warning: Node in arc_definition not found in nodes_ex for plotting graph. Arc: $(arc_def)")
                end
            end

            node_colors_plot = Vector{Symbol}(undef, num_nodes)
            for i in 1:num_nodes
                node_name = id_to_node[i]
                if node_name in configurable_nodes_ex
                    if value(model_gen[:is_open][node_name]) > 0.5
                        node_colors_plot[i] = :green
                    else
                        node_colors_plot[i] = :red
                    end
                else
                    # Ensure node_name exists in node_data_ex before accessing :type
                    if haskey(node_data_ex, node_name)
                        node_type = node_data_ex[node_name][:type]
                        if node_type == :source
                            node_colors_plot[i] = :lightgray
                        elseif node_type == :demand
                            node_colors_plot[i] = :dodgerblue
                        elseif node_type == :intermediate
                            node_colors_plot[i] = :orange
                        else
                            node_colors_plot[i] = :gray # Default for unknown types
                        end
                    else
                        println("Warning: Node $(node_name) not found in node_data_ex for coloring. Defaulting to gray.")
                        node_colors_plot[i] = :gray
                    end
                end
            end

            labels_plot = [String(n) for n in nodes_ex]

            layout_positions = Vector{Point2f}(undef, num_nodes)

            # Dynamically determine echelons and their order
            nodes_by_prefix = Dict{String, Vector{String}}()
            all_prefixes = Set{String}()

            for node_name_any in nodes_ex
                node_name = String(node_name_any) # Ensure it's a string
                prefix = get_node_prefix(node_name)
                push!(all_prefixes, prefix)
                if !haskey(nodes_by_prefix, prefix)
                    nodes_by_prefix[prefix] = String[]
                end
                push!(nodes_by_prefix[prefix], node_name)
            end

            unique_prefixes = collect(all_prefixes)
            ordered_echelon_prefixes = String[]

            if !isempty(unique_prefixes)
                prefix_to_idx = Dict(p => i for (i, p) in enumerate(unique_prefixes))
                idx_to_prefix = Dict(i => p for (p, i) in prefix_to_idx)
                prefix_graph = SimpleDiGraph(length(unique_prefixes))

                for arc_def in arc_definitions_ex
                    from_node_str = String(arc_def[:from])
                    to_node_str = String(arc_def[:to])
                    
                    prefix_from = get_node_prefix(from_node_str)
                    prefix_to = get_node_prefix(to_node_str)

                    if prefix_from != prefix_to && haskey(prefix_to_idx, prefix_from) && haskey(prefix_to_idx, prefix_to)
                        from_idx = prefix_to_idx[prefix_from]
                        to_idx = prefix_to_idx[prefix_to]
                        if from_idx != to_idx # Ensure no self-loops on prefixes if somehow they are different but map to same idx (should not happen with current logic)
                           add_edge!(prefix_graph, from_idx, to_idx)
                        end
                    end
                end
                
                try
                    sorted_indices = topological_sort_by_dfs(prefix_graph)
                    ordered_echelon_prefixes = [idx_to_prefix[i] for i in sorted_indices]
                    
                    # Add any prefixes not in the sorted list (e.g., disconnected, or part of cycles if error wasn't thrown)
                    # This ensures all prefixes are included, typically those not part of the main flow.
                    remaining_prefixes = setdiff(Set(unique_prefixes), Set(ordered_echelon_prefixes))
                    if !isempty(remaining_prefixes)
                        append!(ordered_echelon_prefixes, sort(collect(remaining_prefixes))) # Append them sorted alphabetically
                    end

                catch e
                    if isa(e, ErrorException) && occursin("has a cycle", e.msg) # Check if it's a cycle error
                        println("Warning: Cycle detected in prefix graph, cannot topologically sort echelons. Falling back to alphabetical order. Error: ", e)
                        ordered_echelon_prefixes = sort(unique_prefixes)
                    else
                        println("Warning: Could not topologically sort echelons. Falling back to alphabetical order. Error: ", e)
                        ordered_echelon_prefixes = sort(unique_prefixes) # Fallback for other errors
                    end
                end
                if isempty(ordered_echelon_prefixes) && !isempty(unique_prefixes) # e.g. if all nodes have same prefix, topo sort might be empty
                     ordered_echelon_prefixes = sort(unique_prefixes)
                end
            else
                 println("Warning: No prefixes found for echelon layout.")
            end
            
            if isempty(ordered_echelon_prefixes) && !isempty(nodes_ex)
                println("Warning: Echelon ordering failed. Defaulting to placing all nodes in a single column or using their original indices for positioning if possible.")
                # Fallback: use original node indices or a simple grid if absolutely no echelon info
                 for i in 1:num_nodes
                    if !isassigned(layout_positions, i)
                        layout_positions[i] = Point2f(0, (i % 10) - 5.0) # Basic fallback
                    end
                 end
            end


            current_x = 0.0
            x_increment = 2.5 # Keep existing increment

            for echelon_prefix in ordered_echelon_prefixes
                nodes_in_echelon = sort(get(nodes_by_prefix, echelon_prefix, String[]))
                if isempty(nodes_in_echelon)
                    continue
                end
                num_in_echelon = length(nodes_in_echelon)
                y_spacing_factor = 1.0
                for (j, node_name) in enumerate(nodes_in_echelon)
                    if haskey(node_to_id, node_name)
                        idx = node_to_id[node_name]
                        # Ensure node_name is string for haskey
                        pos_y = (num_in_echelon > 1) ? ((j - 1) - (num_in_echelon - 1) / 2.0) * y_spacing_factor : 0.0
                        layout_positions[idx] = Point2f(current_x, pos_y)
                    else
                        println("Warning: Node $(node_name) from echelon $(echelon_prefix) not found in node_to_id map during layout.")
                    end
                end
                current_x += x_increment
            end

            # Handle any nodes that might not have been assigned a position by the echelon logic
            # (e.g. if get_node_prefix returned UNKNOWN and UNKNOWN wasn't processed or was empty)
            # Or if ordered_echelon_prefixes was empty
            unassigned_nodes_exist = false
            for i in 1:num_nodes
                if !isassigned(layout_positions, i)
                    unassigned_nodes_exist = true
                    node_name_unassigned = id_to_node[i]
                    println("Warning: Node $(node_name_unassigned) was not assigned by echelon logic. Placing at default relative position.")
                    layout_positions[i] = Point2f(current_x, (i % 5) - 2.0) # Place them in a new column or an arbitrary spot
                end
            end
            if unassigned_nodes_exist
                 current_x += x_increment # Increment x if we added an unassigned column
            end


            fig = Figure(resolution = (1024, 768))
            ax = Axis(fig[1,1])

            edge_colors_plot = []
            elabels_plot = Vector{String}(undef, ne(g))
            default_edge_color = Colors.parse(Colorant, :gray40)
            transparent_color = RGBA(0,0,0,0)
            K_scen = keys(pk_ex)

            for (edge_idx, edge) in enumerate(edges(g))
                src_node_idx = Graphs.src(edge)
                dst_node_idx = Graphs.dst(edge)
                
                src_node_name = id_to_node[src_node_idx]
                dst_node_name = id_to_node[dst_node_idx]

                if node_colors_plot[src_node_idx] == :red || node_colors_plot[dst_node_idx] == :red
                    push!(edge_colors_plot, transparent_color)
                    elabels_plot[edge_idx] = ""
                else
                    push!(edge_colors_plot, default_edge_color)
                    scenarios_for_this_arc = []
                    for k in K_scen
                        if haskey(model_gen[:flow], (src_node_name, dst_node_name, k))
                            flow_val = value(model_gen[:flow][src_node_name, dst_node_name, k])
                            if flow_val > 1e-6
                                push!(scenarios_for_this_arc, string(k))
                            end
                        end
                    end
                    if !isempty(scenarios_for_this_arc)
                        elabels_plot[edge_idx] = "S:" * join(scenarios_for_this_arc, ",")
                    else
                        elabels_plot[edge_idx] = ""
                    end
                end
            end

            graphplot!(ax, g,
                layout = layout_positions,
                node_color = node_colors_plot,
                nlabels = labels_plot,
                nlabels_fontsize = 15,
                nlabels_align = (:center, :center),
                node_size = 25,
                arrow_size = 15,
                edge_width = 2,
                edge_color = edge_colors_plot,
                elabels = elabels_plot,
                elabels_fontsize = 10,
                elabels_color = :dimgray,
                elabels_offset = Point2f(0.0, 0.05)
            )
            hidedecorations!(ax)
            hidespines!(ax)

            save(output_filename, fig)
            println("Plot saved to $(output_filename)")
        catch e
            println("Error during plotting: ", e)
            showerror(stdout, e)
            backtrace_e = catch_backtrace()
            Base.show_backtrace(stdout, backtrace_e)
            println()
            @warn "Plotting failed. Ensure Graphs, GraphMakie, CairoMakie, Colors, GeometryBasics are in Project.toml."
        end
    else
        println("Skipping plot generation as the model was not solved optimally. Status: ", termination_status(model_gen))
    end
end 