using Minc2
using Printf
using CLEARSWI
using MriResearchTools
using ArgParse

struct MincData
    mag::AbstractArray
    phase::AbstractArray
    header::Vector{Float64}
    TEs::AbstractVector

    MincData(mag::AbstractArray, 
     phase::AbstractArray, 
     header::Vector{Float64}, 
     TEs=1:size(mag,4)) = new(mag, phase, header, vec(TEs))
end

function getpixdim(data::MincData)::Vector{Float64}
    # hack this is just steps
    data.header
end

CLEARSWI.getpixdim(data::MincData)=getpixdim(data)

function calculateSWI(data::MincData, options::Options=Options())
    if !isnothing(options.writesteps) mkpath(options.writesteps) end
    # standard part
    CLEARSWI.getswimag(data, options) .* CLEARSWI.getswiphase(data, options)
end

function parse_commandline()
    s = ArgParseSettings(
        description = "Apply CLEARSWI algorithm to M3FLASH sequence",
        epilog = """
        Reference: 
        Korbinian Eckstein et all. "Improved susceptibility weighted imaging at ultra-high 
        field using bipolar multi-echo acquisition and optimized image processing: CLEAR-SWI" 
        NeuroImage 2021 https://doi.org/10.1016/j.neuroimage.2021.118175
        """
    )
    @add_arg_table s begin
        "--mag"
            help = "List of mangnitude files, comma separated"
            required = true
            nargs = '+'
            action => :store_arg
        "--pha"
            help = "Input phase files, comma separated"
            required = true
            nargs = '+'
            action => :store_arg
        "--out"
            help = "Output file base"
            required = true
        "--te"
            help = "List of echo times, optional (msec)"
            nargs = '+'
            action => :store_arg

        "--qsm"
            help = """When activated uses RTS QSM for phase weighting.
            """
            action = :store_true
        "--mag-combine"
            help = """SNR | average | echo <n> | SE <te>.
                Magnitude combination algorithm. echo <n> selects a specific
                echo; SE <te> simulates a single echo scan of the given echo
                time."""
            default = ["SNR"]
            nargs = '+'
        "--mag-sensitivity-correction"
            help = """ <filename> | on | off.
                Use the CLEAR-SWI sensitivity correction. Alternatively, a
                sensitivity map can be read from a file"""
            default = "on"
        "--mag-softplus-scaling"
            help = """on | off.
                Set softplus scaling of the magnitude"""
            default = "on"
        "--unwrapping-algorithm"
            help = """laplacian | romeo | laplacianslice"""
            default = "laplacian"
        "--filter-size"
            help = """Size for the high-pass phase filter in voxels. Can be
                given as <x> <y> <z> or in array syntax (e.g. [2.2,3.1,0],
                which is effectively a 2D filter)."""
            nargs = '+'
            default = ["[4,4,0]"]
        "--phase-scaling-type"
            help = """tanh | negativetanh | positive | negative | triangular
                Select the type of phase scaling. positive or negative with a
                strength of 3-6 is used in standard SWI."""
            default = "tanh"
        "--phase-scaling-strength"
            help = """Sets the phase scaling strength. Corresponds to power
                values for positive, negative and triangular phase scaling
                type."""
            default = "4"
        "--writesteps"
            help = """Set to the path of a folder, if intermediate steps should
                be saved."""
            default = nothing

        ##### MINC specific options
        "--float"
            help = """Use floating point for storing the output.
            """
            action = :store_true

    end
    parse_args(ARGS, s)
end


function get_te(minc_file)
    a = Minc2.open_minc_file(minc_file) # acquisition:echo_time
    te = Minc2.get_attribute(a,"acquisition","echo_time")
    Minc2.close_minc_file(a)
    return te
end

history_ = PROGRAM_FILE*" "*Minc2.format_history(ARGS)
args = parse_commandline()

@assert length(args["mag"]) == length(args["pha"])


### decypher options
mag_combine = if args["mag-combine"][1] == "SNR"
                    :SNR
                elseif args["mag-combine"][1] == "average"
                    :average
                elseif args["mag-combine"][1] == "echo"
                    :echo => parse(Int, last(args["mag-combine"]))
                elseif args["mag-combine"][1] == "SE"
                    :SE => parse(Float32, last(args["mag-combine"]))
                else
                    error("The setting for mag-combine is not valid: $(args["mag-combine"])")
                end

mag_sens =  if args["mag-sensitivity-correction"] == "on"
                nothing
            elseif args["mag-sensitivity-correction"] == "off"
                [1]
            elseif isfile(args["mag-sensitivity-correction"])
                args["mag-sensitivity-correction"]
            else
                error("The setting for mag-sensitivity-correction is not valid: $(args["mag-sensitivity-correction"])")
            end

mag_softplus =  if args["mag-softplus-scaling"] == "on"
                    true
                elseif args["mag-softplus-scaling"] == "off"
                    false
                else
                    error("The setting for mag-softplus-scaling is not valid: $(args["mag-softplus-scaling"])")
                end

phase_unwrap = Symbol(args["unwrapping-algorithm"])
phase_hp_sigma = eval(Meta.parse(join(args["filter-size"], " ")))
phase_scaling_type = Symbol(args["phase-scaling-type"])
phase_scaling_strength = try parse(Int, args["phase-scaling-strength"]) catch; parse(Float32, args["phase-scaling-strength"]) end
writesteps = args["writesteps"]
qsm = args["qsm"]

options = Options(;mag_combine, mag_sens, mag_softplus, phase_unwrap, phase_hp_sigma, phase_scaling_type, phase_scaling_strength, writesteps, qsm)
#####

if length(args["te"])>0
    @assert length(args["mag"]) == length(args["te"])
    TEs = parse.(Float64,args["te"])
else # attempt to read from files
    TEs = get_te.(args["mag"]).*1000.0
    @info "TEs(ms)= $TEs"
end

mag=Any[]
pha=Any[]

step=[1.0, 1.0, 1.0]

for (in_mag, in_pha) in zip(args["mag"],args["pha"])
    @info "reading:$(in_mag),$(in_pha)"
    vol_mag = Minc2.read_volume(in_mag, store=Float64)
    vol_pha = Minc2.read_volume(in_pha, store=Float64)
    
    push!(mag, Minc2.array(vol_mag))

    # apply scaling to the phase image
    i,a = extrema(Minc2.array(vol_pha))
    sc = (abs(i)+abs(a))/(2.0*π)

    push!(pha, Minc2.array(vol_pha) ./ sc)

    # get step size
    _,_step,_ = Minc2.decompose(Minc2.voxel_to_world(vol_mag))
    step .= _step[1:3]
end

mag = cat(mag...;dims=4)
pha = cat(pha...;dims=4)

# Calculate t2*
#unwrapped = romeo(phase; mag=mag, TEs=TEs) # type ?romeo in REPL for options
#B0 = calculateB0_unwrapped(unwrapped, mag, TEs) # inverse variance weighted

if false
    t2s_vol = Minc2.empty_volume_like(args["mag"][1], store=Float64)

    Minc2.array(t2s_vol).=NumART2star(mag, TEs)

    # zero out NaNs Inf etc
    Minc2.array(t2s_vol)[.! isfinite.(Minc2.array(t2s_vol))] .= 0.0

    # clamp
    clamp!(Minc2.array(t2s_vol),0.0,1e3)

    Minc2.save_volume(args["out"]*"_t2s.mnc", t2s_vol, store=Float32,history=history_)
end

swi_vol = Minc2.empty_volume_like(args["mag"][1], store=Float64)

Minc2.array(swi_vol) .= calculateSWI(MincData(mag, pha, step, TEs), options)
# zero out NaNs
Minc2.array(swi_vol)[isnan.(Minc2.array(swi_vol))] .= 0.0
## force compression

ENV["MINC_FORCE_V2"]="1"
ENV["MINC_COMPRESS"]="4"


if args["float"]
    Minc2.save_volume(args["out"], swi_vol, store=Float32, history=history_)
else
    Minc2.save_volume(args["out"], swi_vol, store=UInt16, history=history_)
end
