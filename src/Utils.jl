function fields(item::Any)::Dict{String,Any}
    fieldsAndValues = Dict{String,Any}()
    namesOfFields = fieldnames(typeof(item))
    valuesOfFields = map(x -> getfield(item,x), namesOfFields)
    for i in 1:length(namesOfFields)
        push!(fieldsAndValues, string(namesOfFields[i]) => valuesOfFields[i])
    end
    return fieldsAndValues
end