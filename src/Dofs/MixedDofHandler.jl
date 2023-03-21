"""
    Field(name::Symbol, interpolation::Interpolation, dim::Int)

Construct `dim`-dimensional `Field` called `name` which is approximated by `interpolation`.

The interpolation is used for distributing the degrees of freedom.
"""
struct Field
    name::Symbol
    interpolation::Interpolation
    dim::Int
end

"""
    SubDofHandler(fields::Vector{Field}, cellset::Set{Int})

Construct a `SubDofHandler` based on an array of [`Field`](@ref)s and assigns it a set of cells.

A `SubDofHandler` must fullfill the following requirements:
- All [`Cell`](@ref)s in `cellset` are of the same type.
- Each field only uses a single interpolation on the `cellset`.
- Each cell belongs only to a single `SubDofHandler`, i.e. all fields on a cell must be added within the same `FieldHandler`.

Notice that a `SubDofHandler` can hold several fields.
"""
mutable struct SubDofHandler
    fields::Vector{Field}
    cellset::Set{Int}
end

struct CellVector{T}
    values::Vector{T}
    offset::Vector{Int}
    length::Vector{Int}
end

function Base.getindex(elvec::CellVector, el::Int)
    offset = elvec.offset[el]
    return elvec.values[offset:offset + elvec.length[el]-1]
 end

"""
    NewDofHandler(grid::Grid)

Construct a `NewDofHandler` based on `grid`. Supports:
- `Grid`s with or without concrete element type (E.g. "mixed" grids with several different element types.)
- One or several fields, which can live on the whole domain or on subsets of the `Grid`.
"""
struct NewDofHandler{dim,T,G<:AbstractGrid{dim}} <: AbstractDofHandler
    fieldhandlers::Vector{SubDofHandler}
    cell_dofs::CellVector{Int}
    closed::ScalarWrapper{Bool}
    grid::G
    ndofs::ScalarWrapper{Int}
end

function NewDofHandler(grid::Grid{dim,C,T}) where {dim,C,T}
    ncells = getncells(grid)
    NewDofHandler{dim,T,typeof(grid)}(SubDofHandler[], CellVector(Int[],zeros(Int,ncells),zeros(Int,ncells)), ScalarWrapper(false), grid, ScalarWrapper(-1))
end

getfieldnames(fh::SubDofHandler) = [field.name for field in fh.fields]
getfielddims(fh::SubDofHandler) = [field.dim for field in fh.fields]
getfieldinterpolations(fh::SubDofHandler) = [field.interpolation for field in fh.fields]

"""
    ndofs_per_cell(dh::AbstractDofHandler[, cell::Int=1])

Return the number of degrees of freedom for the cell with index `cell`.

See also [`ndofs`](@ref).
"""
ndofs_per_cell(dh::NewDofHandler, cell::Int=1) = dh.cell_dofs.length[cell]
nnodes_per_cell(dh::NewDofHandler, cell::Int=1) = nnodes_per_cell(dh.grid, cell) # TODO: deprecate, shouldn't belong to MixedDofHandler any longer

"""
    celldofs!(global_dofs::Vector{Int}, dh::AbstractDofHandler, i::Int)

Store the degrees of freedom that belong to cell `i` in `global_dofs`.

See also [`celldofs`](@ref).
"""
function celldofs!(global_dofs::Vector{Int}, dh::NewDofHandler, i::Int)
    @assert isclosed(dh)
    @assert length(global_dofs) == ndofs_per_cell(dh, i)
    unsafe_copyto!(global_dofs, 1, dh.cell_dofs.values, dh.cell_dofs.offset[i], length(global_dofs))
    return global_dofs
end

"""
    celldofs(dh::AbstractDofHandler, i::Int)

Return a vector with the degrees of freedom that belong to cell `i`.

See also [`celldofs!`](@ref).
"""
function celldofs(dh::NewDofHandler, i::Int)
    @assert isclosed(dh)
    return dh.cell_dofs[i]
end

#TODO: perspectively remove in favor of `getcoordinates!(global_coords, grid, i)`?
function cellcoords!(global_coords::Vector{Vec{dim,T}}, dh::NewDofHandler, i::Union{Int, <:AbstractCell}) where {dim,T}
    cellcoords!(global_coords, dh.grid, i)
end

function cellnodes!(global_nodes::Vector{Int}, dh::NewDofHandler, i::Union{Int, <:AbstractCell})
    cellnodes!(global_nodes, dh.grid, i)
end

"""
    getfieldnames(dh::NewDofHandler)
    getfieldnames(fh::SubDofHandler)

Return a vector with the names of all fields. Can be used as an iterable over all the fields
in the problem.
"""
function getfieldnames(dh::NewDofHandler)
    fieldnames = Vector{Symbol}()
    for fh in dh.fieldhandlers
        append!(fieldnames, getfieldnames(fh))
    end
    return unique!(fieldnames)
end

getfielddim(fh::SubDofHandler, field_idx::Int) = fh.fields[field_idx].dim
getfielddim(fh::SubDofHandler, field_name::Symbol) = getfielddim(fh, find_field(fh, field_name))

"""
    getfielddim(dh::NewDofHandler, field_idxs::NTuple{2,Int})
    getfielddim(dh::NewDofHandler, field_name::Symbol)
    getfielddim(dh::SubDofHandler, field_idx::Int)
    getfielddim(dh::SubDofHandler, field_name::Symbol)

Return the dimension of a given field. The field can be specified by its index (see
[`find_field`](@ref)) or its name.
"""
function getfielddim(dh::NewDofHandler, field_idxs::NTuple{2, Int})
    fh_idx, field_idx = field_idxs
    fielddim = getfielddim(dh.fieldhandlers[fh_idx], field_idx)
    return fielddim
end
getfielddim(dh::NewDofHandler, name::Symbol) = getfielddim(dh, find_field(dh, name))

"""
    nfields(dh::NewDofHandler)

Returns the number of unique fields defined.
"""
nfields(dh::NewDofHandler) = length(getfieldnames(dh))

"""
    add!(dh::NewDofHandler, fh::SubDofHandler)

Add all fields of the [`SubDofHandler`](@ref) `fh` to `dh`.
"""
function add!(dh::NewDofHandler, fh::SubDofHandler)
    # TODO: perhaps check that a field with the same name is the same field?
    @assert !isclosed(dh)
    _check_same_celltype(dh.grid, collect(fh.cellset))
    _check_cellset_intersections(dh, fh)
    # the field interpolations should have the same refshape as the cells they are applied to
    refshapes_fh = getrefshape.(getfieldinterpolations(fh))
    # extract the celltype from the first cell as the celltypes are all equal
    cell_type = typeof(dh.grid.cells[first(fh.cellset)])
    refshape_cellset = getrefshape(default_interpolation(cell_type))
    for refshape in refshapes_fh
        refshape_cellset == refshape || error("The RefShapes of the fieldhandlers interpolations must correspond to the RefShape of the cells it is applied to.")
    end

    push!(dh.fieldhandlers, fh)
    return dh
end

function _check_cellset_intersections(dh::NewDofHandler, fh::SubDofHandler)
    for _fh in dh.fieldhandlers
        isdisjoint(_fh.cellset, fh.cellset) || error("Each cell can only belong to a single SubDofHandler.")
    end
end

function add!(dh::NewDofHandler, name::Symbol, dim::Int)
    celltype = getcelltype(dh.grid)
    isconcretetype(celltype) || error("If you have more than one celltype in Grid, you must use add!(dh::NewDofHandler, fh::SubDofHandler)")
    add!(dh, name, dim, default_interpolation(celltype))
end

function add!(dh::NewDofHandler, name::Symbol, dim::Int, ip::Interpolation)
    @assert !isclosed(dh)

    celltype = getcelltype(dh.grid)
    @assert isconcretetype(celltype)

    if length(dh.fieldhandlers) == 0
        cellset = Set(1:getncells(dh.grid))
        push!(dh.fieldhandlers, SubDofHandler(Field[], cellset))
    elseif length(dh.fieldhandlers) > 1
        error("If you have more than one SubDofHandler, you must specify field")
    end
    fh = first(dh.fieldhandlers)

    field = Field(name,ip,dim)

    push!(fh.fields, field)

    return dh
end

"""
    close!(dh::AbstractDofHandler)

Closes `dh` and creates degrees of freedom for each cell.

If there are several fields, the dofs are added in the following order:
For a `NewDofHandler`, go through each `SubDofHandler` in the order they were added.
For each field in the `SubDofHandler` or in the `DofHandler` (again, in the order the fields were added),
create dofs for the cell.
This means that dofs on a particular cell, the dofs will be numbered according to the fields;
first dofs for field 1, then field 2, etc.
"""
function close!(dh::NewDofHandler)
    dh, _, _, _ = __close!(dh)
    return dh
end

function __close!(dh::NewDofHandler{dim}) where {dim}
    @assert !isclosed(dh)
    field_names = getfieldnames(dh)  # all the fields in the problem
    numfields =  length(field_names)

    # Create dicts that store created dofs
    # Each key should uniquely identify the given type
    vertexdicts = [Dict{Int, UnitRange{Int}}() for _ in 1:numfields]
    edgedicts = [Dict{Tuple{Int,Int}, UnitRange{Int}}() for _ in 1:numfields]
    facedicts = [Dict{NTuple{dim,Int}, UnitRange{Int}}() for _ in 1:numfields]
    celldicts = [Dict{Int, UnitRange{Int}}() for _ in 1:numfields]

    # Set initial values
    nextdof = 1  # next free dof to distribute

    @debug "\n\nCreating dofs\n"
    for fh in dh.fieldhandlers
        # sort the cellset since we want to loop through the cells in a fixed order
        cellnumbers = sort(collect(fh.cellset))
        nextdof = _close!(
            dh,
            cellnumbers,
            field_names,
            getfieldnames(fh),
            getfielddims(fh),
            getfieldinterpolations(fh),
            nextdof,
            vertexdicts,
            edgedicts,
            facedicts,
            celldicts)
    end
    dh.ndofs[] = maximum(dh.cell_dofs.values)
    dh.closed[] = true

    return dh, vertexdicts, edgedicts, facedicts

end

function _close!(dh::NewDofHandler{dim}, cellnumbers, global_field_names, field_names, field_dims, field_interpolations, nextdof, vertexdicts, edgedicts, facedicts, celldicts) where {dim}
    ip_infos = InterpolationInfo[]
    for interpolation in field_interpolations
        ip_info = InterpolationInfo(interpolation)
        # these are not implemented yet (or have not been tested)
        @assert(all(ip_info.nedgedofs .<= 1))
        @assert(all(ip_info.nfacedofs .<= 1))
        push!(ip_infos, ip_info)
    end

    # loop over all the cells, and distribute dofs for all the fields
    cell_dofs = Int[]  # list of global dofs for each cell
    for ci in cellnumbers
        dh.cell_dofs.offset[ci] = length(dh.cell_dofs.values)+1

        cell = dh.grid.cells[ci]
        empty!(cell_dofs)
        @debug "Creating dofs for cell #$ci"

        for (local_num, field_name) in enumerate(field_names)
            fi = findfirst(i->i == field_name, global_field_names)
            @debug "\tfield: $(field_name)"
            ip_info = ip_infos[local_num]

            # We first distribute the vertex dofs
            nextdof = add_vertex_dofs(cell_dofs, cell, vertexdicts[fi], field_dims[local_num], ip_info.nvertexdofs, nextdof)

            # Then the edge dofs
            if dim == 3
                if ip_info.dim == 3 # Regular 3D element
                    nextdof = add_edge_dofs(cell_dofs, cell, edgedicts[fi], field_dims[local_num], ip_info.nedgedofs, nextdof)
                elseif ip_info.dim == 2 # 2D embedded element in 3D
                    nextdof = add_edge_dofs(cell_dofs, cell, edgedicts[fi], field_dims[local_num], ip_info.nfacedofs, nextdof)
                end
            end

            # Then the face dofs
            if ip_info.dim == dim # Regular 3D element
                nextdof = add_face_dofs(cell_dofs, cell, facedicts[fi], field_dims[local_num], ip_info.nfacedofs, nextdof)
            end

            # And finally the celldofs
            nextdof = add_cell_dofs(cell_dofs, ci, celldicts[fi], field_dims[local_num], ip_info.ncelldofs, nextdof)
        end
        # after done creating dofs for the cell, push them to the global list
        append!(dh.cell_dofs.values, cell_dofs)
        dh.cell_dofs.length[ci] = length(cell_dofs)

        @debug "Dofs for cell #$ci:\n\t$cell_dofs"
    end # cell loop
    return nextdof
end

"""
Returns the next global dof number and an array of dofs.
If dofs have already been created for the object (vertex, face) then simply return those, otherwise create new dofs.
"""
function get_or_create_dofs!(nextdof, field_dim; dict, key)
    token = Base.ht_keyindex2!(dict, key)
    if token > 0  # vertex, face etc. visited before
        # reuse stored dofs (TODO unless field is discontinuous)
        @debug "\t\tkey: $key dofs: $(dict[key])  (reused dofs)"
        return nextdof, dict[key]
    else  # create new dofs
        dofs = nextdof : (nextdof + field_dim-1)
        @debug "\t\tkey: $key dofs: $dofs"
        Base._setindex!(dict, dofs, key, -token) #
        nextdof += field_dim
        return nextdof, dofs
    end
end

function add_vertex_dofs(cell_dofs, cell, vertexdict, field_dim, nvertexdofs, nextdof)
    for (vi, vertex) in enumerate(vertices(cell))
        if nvertexdofs[vi] > 0
            @debug "\tvertex #$vertex"
            nextdof, dofs = get_or_create_dofs!(nextdof, field_dim, dict=vertexdict, key=vertex)
            append!(cell_dofs, dofs)
        end
    end
    return nextdof
end

function add_face_dofs(cell_dofs, cell, facedict, field_dim, nfacedofs, nextdof)
    @debug @assert all(nfacedofs .<= 1) "Currently only supports interpolations with less that 2 dofs per face"

    for (fi,face) in enumerate(faces(cell))
        if nfacedofs[fi] > 0
            sface = sortface(face)
            @debug "\tface #$sface"
            nextdof, dofs = get_or_create_dofs!(nextdof, field_dim, dict=facedict, key=sface)
            # TODO permutate dofs according to face orientation
            append!(cell_dofs, dofs)
        end
    end
    return nextdof
end

function add_edge_dofs(cell_dofs, cell, edgedict, field_dim, nedgedofs, nextdof)
    for (ei,edge) in enumerate(edges(cell))
        if nedgedofs[ei] > 0
            sedge, dir = sortedge(edge)
            @debug "\tedge #$sedge"
            nextdof, dofs = get_or_create_dofs!(nextdof, field_dim, dict=edgedict, key=sedge)
            append!(cell_dofs, dofs)
        end
    end
    return nextdof
end

function add_cell_dofs(cell_dofs, cell, celldict, field_dim, ncelldofs, nextdof)
    for celldof in 1:ncelldofs
        @debug "\tcell #$cell"
        nextdof, dofs = get_or_create_dofs!(nextdof, field_dim, dict=celldict, key=cell)
        append!(cell_dofs, dofs)
    end
    return nextdof
end

"""
    find_field(dh::NewDofHandler, field_name::Symbol)::NTuple{2,Int}

Return the index of the field with name `field_name` in a `NewDofHandler`. The index is a
`NTuple{2,Int}`, where the 1st entry is the index of the `SubDofHandler` within which the
field was found and the 2nd entry is the index of the field within the `SubDofHandler`.

!!! note
    Always finds the 1st occurence of a field within `NewDofHandler`.

See also: [`find_field(fh::SubDofHandler, field_name::Symbol)`](@ref),
[`_find_field(fh::SubDofHandler, field_name::Symbol)`](@ref).
"""
function find_field(dh::NewDofHandler, field_name::Symbol)
    for (fh_idx, fh) in pairs(dh.fieldhandlers)
        field_idx = _find_field(fh, field_name)
        !isnothing(field_idx) && return (fh_idx, field_idx)
    end
    error("Did not find field :$field_name (existing fields: $(getfieldnames(dh))).")
end

"""
    find_field(fh::SubDofHandler, field_name::Symbol)::Int

Return the index of the field with name `field_name` in a `SubDofHandler`. Throw an
error if the field is not found.

See also: [`find_field(dh::NewDofHandler, field_name::Symbol)`](@ref), [`_find_field(fh::SubDofHandler, field_name::Symbol)`](@ref).
"""
function find_field(fh::SubDofHandler, field_name::Symbol)
    field_idx = _find_field(fh, field_name)
    if field_idx === nothing
        error("Did not find field :$field_name in SubDofHandler (existing fields: $(getfieldnames(fh)))")
    end
    return field_idx
end

# No error if field not found
"""
    _find_field(fh::SubDofHandler, field_name::Symbol)::Int

Return the index of the field with name `field_name` in the `SubDofHandler` `fh`. Return 
`nothing` if the field is not found.

See also: [`find_field(dh::NewDofHandler, field_name::Symbol)`](@ref), [`find_field(fh::SubDofHandler, field_name::Symbol)`](@ref).
"""
function _find_field(fh::SubDofHandler, field_name::Symbol)
    for (field_idx, field) in pairs(fh.fields)
        if field.name == field_name
            return field_idx
        end
    end
    return nothing
end

# Calculate the offset to the first local dof of a field
function field_offset(fh::SubDofHandler, field_idx::Int)
    offset = 0
    for i in 1:(field_idx-1)
        offset += getnbasefunctions(fh.fields[i].interpolation)::Int * fh.fields[i].dim
    end
    return offset
end
field_offset(fh::SubDofHandler, field_name::Symbol) = field_offset(fh, find_field(fh, field_name))

field_offset(dh::NewDofHandler, field_name::Symbol) = field_offset(dh, find_field(dh, field_name))
function field_offset(dh::NewDofHandler, field_idxs::Tuple{Int, Int})
    fh_idx, field_idx = field_idxs
    field_offset(dh.fieldhandlers[fh_idx], field_idx)
end

"""
    dof_range(fh::SubDofHandler, field_idx::Int)
    dof_range(fh::SubDofHandler, field_name::Symbol)
    dof_range(dh:NewDofHandler, field_name::Symbol)

Return the local dof range for a given field. The field can be specified by its name or
index, where `field_idx` represents the index of a field within a `SubDofHandler` and
`field_idxs` is a tuple of the `SubDofHandler`-index within the `NewDofHandler` and the
`field_idx`.

!!! note
    The `dof_range` of a field can vary between different `SubDofHandler`s. Therefore, it is
    advised to use the `field_idxs` or refer to a given `SubDofHandler` directly in case
    several `SubDofHandler`s exist. Using the `field_name` will always refer to the first
    occurence of `field` within the `NewDofHandler`.

Example:
```jldoctest
julia> grid = generate_grid(Triangle, (3, 3))
Grid{2, Triangle, Float64} with 18 Triangle cells and 16 nodes

julia> dh = NewDofHandler(grid); add!(dh, :u, 3); add!(dh, :p, 1); close!(dh);

julia> dof_range(dh, :u)
1:9

julia> dof_range(dh, :p)
10:12

julia> dof_range(dh, (1,1)) # field :u
1:9

julia> dof_range(dh.fieldhandlers[1], 2) # field :p
10:12
```
"""
function dof_range(fh::SubDofHandler, field_idx::Int)
    offset = field_offset(fh, field_idx)
    field_interpolation = fh.fields[field_idx].interpolation
    field_dim = fh.fields[field_idx].dim
    n_field_dofs = getnbasefunctions(field_interpolation)::Int * field_dim
    return (offset+1):(offset+n_field_dofs)
end
dof_range(fh::SubDofHandler, field_name::Symbol) = dof_range(fh, find_field(fh, field_name))

function dof_range(dh::NewDofHandler, field_name::Symbol)
    if length(dh.fieldhandlers) > 1
        error("The given NewDofHandler has $(length(dh.fieldhandlers)) SubDofHandlers.
              Extracting the dof range based on the fieldname might not be a unique problem
              in this case. Use `dof_range(fh::SubDofHandler, field_name)` instead.")
    end
    fh_idx, field_idx = find_field(dh, field_name)
    return dof_range(dh.fieldhandlers[fh_idx], field_idx)
end

"""
    getfieldinterpolation(dh::NewDofHandler, field_idxs::NTuple{2,Int})
    getfieldinterpolation(dh::SubDofHandler, field_idx::Int)
    getfieldinterpolation(dh::SubDofHandler, field_name::Symbol)

Return the interpolation of a given field. The field can be specified by its index (see
[`find_field`](@ref) or its name.
"""
function getfieldinterpolation(dh::NewDofHandler, field_idxs::NTuple{2,Int})
    fh_idx, field_idx = field_idxs
    ip = dh.fieldhandlers[fh_idx].fields[field_idx].interpolation
    return ip
end
getfieldinterpolation(fh::SubDofHandler, field_idx::Int) = fh.fields[field_idx].interpolation
getfieldinterpolation(fh::SubDofHandler, field_name::Symbol) = getfieldinterpolation(fh, find_field(fh, field_name))

function reshape_to_nodes(dh::NewDofHandler, u::Vector{T}, fieldname::Symbol) where T
    # make sure the field exists
    fieldname ∈ getfieldnames(dh) || error("Field $fieldname not found.")

    field_dim = getfielddim(dh, fieldname)
    space_dim = field_dim == 2 ? 3 : field_dim
    data = fill(T(NaN), space_dim, getnnodes(dh.grid))  # set default value

    for fh in dh.fieldhandlers
        # check if this fh contains this field, otherwise continue to the next
        field_pos = findfirst(i->i == fieldname, getfieldnames(fh))
        field_pos === nothing && continue
        offset = field_offset(fh, fieldname)

        reshape_field_data!(data, dh, u, offset, field_dim, fh.cellset)
    end
    return data
end
