"""
Provides functionality for working with database migrations.
"""
module Migration

import Millboard, Dates, Logging, DataFrames
using SearchLight
import Base.showerror

mutable struct DatabaseMigration # todo: rename the "migration_" prefix for the fields
  migration_hash::String
  migration_file_name::String
  migration_module_name::String
end


struct IrreversibleMigrationException <: Exception
  migration_name::Symbol
end
Base.showerror(io::IO, e::IrreversibleMigrationException) = print(io, "Migration $(e.migration_name) is not reversible")


struct ExistingMigrationException <: Exception
  migration_name::Union{Symbol,String}
end
Base.showerror(io::IO, e::ExistingMigrationException) = print(io, "Migration $(e.migration_name) already exists")

struct MigrationNotFoundException <: Exception
  migration_module::String
end
Base.showerror(io::IO, e::MigrationNotFoundException) = print(io, "Migration $(e.migration_module) can not be found")


"""
    newtable(migration_name::String, resource::String) :: Nothing

Creates a new default migration file and persists it to disk in the configured migrations folder.
"""
function new_table(migration_name::String, resource::String) :: Nothing
  mfn = migration_file_name(migration_name)

  ispath(mfn) && throw(ExistingMigrationException(migration_name))
  ispath(SearchLight.config.db_migrations_folder) || mkpath(SearchLight.config.db_migrations_folder)

  open(mfn, "w") do f
    write(f, SearchLight.Generator.FileTemplates.new_table_migration(migration_module_name(migration_name), resource))
  end

  @info "New table migration created at $(abspath(mfn))"

  nothing
end

function names_and_types(modelType::Type{T}) where {T<:SearchLight.AbstractModel}

  storableNames = SearchLight.fields_to_store_directly(modelType)
  dictFieldTypes = SearchLight.to_string_dict(modelType)
  
  primary_key_Model = pk(modelType)
  names_and_types = ""

  for (field,column) in storableNames
    if field != primary_key_Model
      ## because of Modul.Type splitting is nesessary 
      tmpField = string(Base.last(split(string(dictFieldTypes[field]),".")))
      names_and_types = string(names_and_types , "column(:",column , "  ,:",lowercase(tmpField),")", "\r\n")
    elseif  field == primary_key_Model
      names_and_types = string(names_and_types, "primary_key() \r\n")
    end
  end

  return names_and_types
end

function new_table(migration_name::String , modelType::Type{T} , resource::String) where {T<:SearchLight.AbstractModel}
  mfn = migration_file_name(migration_name)

  ispath(mfn) && throw(ExistingMigrationException(migration_name))
  ispath(SearchLight.config.db_migrations_folder) || mkpath(SearchLight.config.db_migrations_folder)

  
  names_and_typesString_of_types = names_and_types(modelType)

  open(mfn, "w") do f
    write(f, SearchLight.Generator.FileTemplates.new_table_migration(migration_module_name(migration_name), names_and_typesString_of_types , resource))
  end

  @info "New table migration created at $(abspath(mfn))"

  nothing
end

const newtable = new_table


"""
"""
function new(migration_name::String) :: Nothing
  mfn = migration_file_name(migration_name)

  ispath(mfn) && throw(ExistingMigrationException(migration_name))
  ispath(SearchLight.config.db_migrations_folder) || mkpath(SearchLight.config.db_migrations_folder)

  open(mfn, "w") do f
    write(f, SearchLight.Generator.FileTemplates.newmigration(migration_module_name(migration_name)))
  end

  @info "New migration created at $(abspath(mfn))"

  nothing
end


"""
    migration_hash() :: String

Computes a unique hash for a migration identifier.
"""
function migration_hash() :: String
  m = match(r"(\d*)-(\d*)-(\d*)T(\d*):(\d*):(\d*)\.(\d*)", "$(Dates.unix2datetime(time()))")

  rpad(join(m.captures), 16, "0")[1:16]
end


"""
    migration_file_name(migration_name::String) :: String
    migration_file_name(cmd_args::Dict{String,Any}, config::Configuration.Settings) :: String

Computes the name of a new migration file.
"""
function migration_file_name(migration_name::String) :: String
  joinpath(SearchLight.config.db_migrations_folder, migration_hash() * "_" * migration_name * ".jl")
end
function migration_file_name(cmd_args::Dict{String,Any}, config::SearchLight.Configuration.Settings) :: String
  joinpath(config.db_migrations_folder, migration_hash() * "_" * cmd_args["migration:new"] * ".jl")
end


"""
    migration_module_name(underscored_migration_name::String) :: String

Computes the name of the module of the migration based on the input from the user (migration name).
"""
function migration_module_name(underscored_migration_name::String) :: String
  mapreduce( x -> uppercasefirst(x), *, split(replace(underscored_migration_name, ".jl"=>""), "_") )
end


"""
    last_up(; force = false) :: Nothing

Migrates up the last migration. If `force` is `true`, the migration will be executed even if it's already up.
"""
function last_up(; force = false) :: Nothing
  run_migration(last_migration(), :up, force = force)
end
function up(; force = false) :: Nothing
  last_up(force = force)
end

const lastup = last_up


"""
    last_down() :: Nothing

Migrates down the last migration. If `force` is `true`, the migration will be executed even if it's already down.
"""
function last_down(; force = false) :: Nothing
  run_migration(last_migration(), :down, force = force)
end
function down(; force = false) :: Nothing
  last_down(force = force)
end

const lastdown = last_down


"""
    up(migration_module_name::String; force::Bool = false) :: Nothing
    up_by_module_name(migration_module_name::String; force::Bool = false) :: Nothing

Runs up the migration corresponding to `migration_module_name`.
"""
function up(migration_module_name::String; force::Bool = false) :: Nothing
  migration = migration_by_module_name(migration_module_name)
  migration !== nothing ?
    run_migration(migration, :up, force = force) :
    throw(MigrationNotFoundException(migration_module_name))
end
function up_by_module_name(migration_module_name::Union{String,Symbol,Module}; force::Bool = false) :: Nothing
  up(migration_module_name |> string, force = force)
end


"""
    down(migration_module_name::String; force::Bool = false) :: Nothing
    down_by_module_name(migration_module_name::String; force::Bool = false) :: Nothing

Runs down the migration corresponding to `migration_module_name`.
"""
function down(migration_module_name::String; force::Bool = false) :: Nothing
  migration = migration_by_module_name(migration_module_name)
  migration !== nothing ?
    run_migration(migration, :down, force = force) :
    throw(MigrationNotFoundException(migration_module_name))
end
function down_by_module_name(migration_module_name::Union{String,Symbol,Module}; force::Bool = false) :: Nothing
  down(migration_module_name |> string, force = force)
end


"""
    migration_by_module_name(migration_module_name::String) :: Union{Nothing,DatabaseMigration}

Computes the migration that corresponds to `migration_module_name`.
"""
function migration_by_module_name(migration_module_name::String) :: Union{Nothing,DatabaseMigration}
  ids, migrations = all_migrations()

  for id in ids
    migration = migrations[id]
    if migration.migration_module_name == migration_module_name
      return migration
    end
  end

  nothing
end


"""
    all_migrations() :: Tuple{Vector{String},Dict{String,DatabaseMigration}}

Returns the list of all the migrations.
"""
function all_migrations() :: Tuple{Vector{String},Dict{String,DatabaseMigration}}
  migrations = String[]
  migrations_files = Dict{String,DatabaseMigration}()
  for f in readdir(SearchLight.config.db_migrations_folder)
    if occursin(r"\d{16,17}_.*\.jl", f)
      parts = map(x -> String(x), split(f, "_", limit = 2))
      push!(migrations, parts[1])
      migrations_files[parts[1]] = DatabaseMigration(parts[1], f, migration_module_name(parts[2]))
    end
  end

  sort!(migrations), migrations_files
end

const all = all_migrations


"""
    last_migration() :: DatabaseMigration

Returns the last created migration.
"""
function last_migration() :: DatabaseMigration
  migrations, migrations_files = all_migrations()
  migrations_files[migrations[end]]
end

const last = last_migration


"""
    run_migration(migration::DatabaseMigration, direction::Symbol; force = false) :: Nothing

Runs `migration` in up or down, per `directon`. If `force` is true, the migration is run regardless of its current status (already `up` or `down`).
"""
function run_migration(migration::DatabaseMigration, direction::Symbol; force = false) :: Nothing
  if ! force
    if  ( direction == :up    && in(migration.migration_hash, upped_migrations()) ) ||
        ( direction == :down  && in(migration.migration_hash, downed_migrations()) )
      @warn "Skipping, migration is already $direction"

      return
    end
  end

  try
    m = include(abspath(joinpath(SearchLight.config.db_migrations_folder, migration.migration_file_name)))
    if in(:disabled, names(m, all = true)) && m.disabled && ! force
      @warn "Skipping, migration is disabled"

      return
    end
    Base.invokelatest(getfield(m, direction))

    store_migration_status(migration, direction, force = force)

    @info "Executed migration $(migration.migration_module_name) $(direction)"
  catch ex
    @error "Failed executing migration $(migration.migration_module_name) $(direction)"

    rethrow(ex)
  end

  nothing
end


"""
    store_migration_status(migration::DatabaseMigration, direction::Symbol) :: Nothing

Persists the `direction` of the `migration` into the database.
"""
function store_migration_status(migration::DatabaseMigration, direction::Symbol; force = false) :: Nothing
  try
    if direction == :up
      queryString = "INSERT INTO $(SearchLight.config.db_migrations_table_name) VALUES ('$(migration.migration_hash)')"
      println(queryString)
      SearchLight.query(queryString, internal = true)
    else
      SearchLight.query("DELETE FROM $(SearchLight.config.db_migrations_table_name) WHERE version = ('$(migration.migration_hash)')", internal = true)
    end
  catch ex
    @error ex

    force || rethrow(ex)
  end

  nothing
end


"""
    upped_migrations() :: Vector{String}

List of all migrations that are `up`.
"""
function upped_migrations() :: Vector{String}
  result = SearchLight.query("SELECT version FROM $(SearchLight.config.db_migrations_table_name) ORDER BY VERSION DESC"; internal = true)

  if DataFrames.nrow(result) > 0
    #Choosing direct index because some db systems every time give back the uppercase of the column name
    String[string(x) for x = result[!, 1]]
  else
    String[]
  end
end


"""
    downed_migrations() :: Vector{String}

List of all migrations that are `down`.
"""
function downed_migrations() :: Vector{String}
  upped = upped_migrations()
  filter(m -> ! in(m, upped), all_migrations()[1])
end


"""
    status() :: Nothing

Prints a table that displays the `direction` of each migration.
"""
function status() :: Nothing
  migrations, migrations_files = all_migrations()
  up_migrations = upped_migrations()
  arr_output = []

  for m in migrations
    # sts = ( findfirst(up_migrations, m) > 0 ) ? :up : :down
    sts = something(findfirst(isequal(m), up_migrations), 0) > 0 ? :up : :down
    push!(arr_output, [migrations_files[m].migration_module_name * ": " * uppercase(string(sts)); migrations_files[m].migration_file_name])
  end

  Millboard.table(arr_output, colnames = ["Module name & status \nFile name "], rownames = []) |> println

  nothing
end


"""
    all_with_status() :: Tuple{Vector{String},Dict{String,Dict{Symbol,Any}}}

Returns a list of all the migrations and their status.
"""
function all_with_status() :: Tuple{Vector{String},Dict{String,Dict{Symbol,Any}}}
  migrations, migrations_files = all_migrations()
  up_migrations = upped_migrations()
  indexes = String[]
  result = Dict{String,Dict{Symbol,Any}}()

  for m in migrations
    # status = ( findfirst(up_migrations, m) > 0 ) ? :up : :down
    status = something(findfirst(isequal(m), up_migrations), 0) > 0 ? :up : :down
    push!(indexes, migrations_files[m].migration_hash)
    result[migrations_files[m].migration_hash] = Dict(
      :migration => DatabaseMigration(migrations_files[m].migration_hash, migrations_files[m].migration_file_name, migrations_files[m].migration_module_name),
      :status => status
    )
  end

  indexes, result
end


"""
    all_down!!() :: Nothing

Runs all migrations `down`.
"""
function all_down!!(; confirm = true) :: Nothing
  if confirm
    printstyled("!!!WARNING!!! This will run down all the migration, potentially leading to irrecuperable data loss! You have 10 seconds to cancel this. ", color = :yellow)
    sleep(5)
    printstyled("Running down all the migrations in 5 seconds. ", :yellow)
    sleep(5)
  end

  i, m = all_with_status()
  for v in values(m)
    if v[:status] == :up
      mm = v[:migration]
      down_by_module_name(mm.migration_module_name)
    end
  end

  nothing
end


"""
    all_up!!() :: Nothing

Runs all migrations `up`.
"""
function all_up!!() :: Nothing
  i, m = all_with_status()
  for v_hash in i
    v = m[v_hash]
    if v[:status] == :down
      mm = v[:migration]
      up_by_module_name(mm.migration_module_name)
    end
  end

  nothing
end


function create_table end


function column end


function column_id end
const primary_key = column_id


function add_index end


function add_column end


function drop_table end


function remove_column end


function remove_index end


function create_sequence end


function constraint end


function nextval end


function column_id_sequence end


function remove_sequence end


const drop_sequence = remove_sequence


function create_migrations_table end

function drop_migrations_table end

function reset_sequence end

end

const Migrations = Migration
