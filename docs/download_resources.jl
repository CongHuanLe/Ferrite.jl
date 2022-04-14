# Download some assets necessary for docs/testing not stored in the repo
import Downloads

const directory = joinpath(@__DIR__, "src", "examples")
mkpath(directory)

for (file, url) in [
        "periodic-rve.msh" => "https://raw.githubusercontent.com/Ferrite-FEM/Ferrite.jl/gh-pages/assets/periodic-rve.msh",
        "periodic-rve-coarse.msh" => "https://raw.githubusercontent.com/Ferrite-FEM/Ferrite.jl/gh-pages/assets/periodic-rve-coarse.msh",
        "porous_media_0p25.inp" => "https://raw.githubusercontent.com/Ferrite-FEM/Ferrite.jl/kam/MixedDofHandlerExample/docs/src/literate/porous_media_0p25.inp",
    ]
    afile = joinpath(directory, file)
    if !isfile(afile)
        Downloads.download(url, afile)
    end
end
