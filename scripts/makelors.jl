push!(LOAD_PATH,"../src/")
using DrWatson
@quickactivate "JPetalo"
include("../src/jpetalo.jl")

using DataFrames
using Glob

"""
	makelor_3p(files::Vector{String},
			   ecut::Float64=4.0, file_i=1, file_l=1)

	Take a vector of files containing PETALO data and compute LORS
	TLR  : A DataFrame of True Lors
	RLHB : A DataFrame of Reco Lors with HALF algorithm and barycenter
	RLKB : A DataFrame of Reco Lors with kmeans algorithm and barycenter
	RLKK : A DataFrame of Reco Lors with kmeans algorithm and kcluster

	Events are pre-selected to be primary photoelectric in LXe
	with two and only two gammas

"""
function makelor_3p(files::Vector{String}, fxy=JPetalo.lor_kmeans,
	                ecut::Float64=4.0, file_i=1, file_l=1)

	# true reconstructed LOR
	TLR = [(t1=0.0,t2=0.0,x1=0.0,y1=0.0,z1=0.0,x2=0.0,y2=0.0,z2=0.0)]
	# LOR reconstructed from barycenter
	RLB = [(t1=0.0,t2=0.0,x1=0.0,y1=0.0,z1=0.0,x2=0.0,y2=0.0,z2=0.0)]
	# LOR corrected using R
	RLR = [(t1=0.0,t2=0.0,x1=0.0,y1=0.0,z1=0.0,x2=0.0,y2=0.0,z2=0.0)]
	# RLHB = [(t1=0.0,t2=0.0,x1=0.0,y1=0.0,z1=0.0,x2=0.0,y2=0.0,z2=0.0)]
	# RLKB = [(t1=0.0,t2=0.0,x1=0.0,y1=0.0,z1=0.0,x2=0.0,y2=0.0,z2=0.0)]
	# RLKK = [(t1=0.0,t2=0.0,x1=0.0,y1=0.0,z1=0.0,x2=0.0,y2=0.0,z2=0.0)]


	for file in files[file_i:file_l]               # loop on files
		println("reading file = ", file)
		pdf = JPetalo.read_abc(file)            # read file
		dfs = JPetalo.primary_phot_in_lxe(pdf)  # primary photons in LXe

		cevt = 0

		for event in dfs.event_id              #loop on eventa

			#  event DF
			vdf = JPetalo.select_by_column_value(dfs, "event_id", event)
			if nrow(vdf) == 2  && event != cevt    # only 2 gammas
				# select true
				df1 = JPetalo.select_by_column_value(vdf, "track_id", 1)
				df2 = JPetalo.select_by_column_value(vdf, "track_id", 2)
				push!(TLR, (t1=df1.t[1],t2=df2.t[1],
						    x1=df1.x[1],y1=df1.y[1],z1=df1.z[1],
						    x2=df2.x[1],y2=df2.y[1],z2=df2.z[1]))

				#select reco
				hitdf  = JPetalo.reco_hits(event, ecut, pdf)
				#b1, b2 = JPetalo.lor_maxq(hitdf)
				#rb1, rb2 = JPetalo.lor_kmeans(hitdf)

				# reconstruct (x,y) : barycenter
				b1, b2 = fxy(hitdf)

				# find R1 and R2 (from True info)

				R1 = sqrt(df1.x[1]^2 + df1.y[1]^2)
				R2 = sqrt(df2.x[1]^2 + df2.y[1]^2)

				# New (x,y) positions estimated from R1 and R2
				x1,y1,z1  = rxyz(b1, R1)
				x2,y2,z2  = rxyz(b2, R2)

				push!(RLR, (t1=df1.t[1],t2=df2.t[1],
						    x1=x1,y1=y1,z1=z1,
						    x2=x2,y2=y2,z2=z2))

				push!(RLB, (t1=df1.t[1],t2=df2.t[1],
						    x1=b1.x,y1=b1.y,z1=b1.z,
						    x2=b2.x,y2=b2.y,z2=b2.z))

				# push!(RLKK, (t1=df1.t[1],t2=df2.t[1],
				# 		    x1=kb1.x,y1=kb1.y,z1=kb1.z,
				# 		    x2=kb2.x,y2=kb2.y,z2=kb2.z))

				# correct barycenter

				cevt = event
			end
		end
	end
		return DataFrame(TLR[2:end]),
		       DataFrame(RLB[2:end]),
			   DataFrame(RLR[2:end])
end

"""
	df_to_mlemlor(ldf::DataFrame)

Take a LOR Data Frame and return a vector of MlemLor, suitable for hdf5
"""
function df_to_mlemlor(ldf::DataFrame)
	ml = [JPetalo.MlemLor(ldf.t1[i], ldf.t2[i],
		          ldf.x1[i],ldf.y1[i],ldf.z1[i],
				  ldf.x2[i],ldf.y2[i],ldf.z2[i]) for i in 1:nrow(ldf)]
	return ml
end

function rxyz(b::JPetalo.Hit, R::Float32)
	θ = atan(b.y, b.x)
	ϕ = atan(b.z, R)
	x = R * cos(θ)
	y = R * sin(θ)
	z = R * sin(ϕ)
	return x,y,z
end

function makelors()
	ecut = 4.0

	println("+++makelor: ecut (in pes) = ", ecut)

	dr = datadir("nema3-vac-1m")
	files = glob("*.h5",dr)

	println("number of files in data dir = ", length(files))
	file_i = 31
	file_l = 40

	println("reading =", file_l - file_i + 1, " files")

	#tldf, rlhbdf, rlkbdf, rlkkdf = makelor_3p(files, 4.0, file_i, file_l)
	tldf, rlbdf, rlrdf = makelor_3p(files, JPetalo.lor_kmeans,
	                                4.0, file_i, file_l)

	mtl   = df_to_mlemlor(tldf)
	mrlb  = df_to_mlemlor(rlbdf)
	mrlr  = df_to_mlemlor(rlrdf)
	#mrlkk = df_to_mlemlor(rlkkdf)

	smtl  = string("nema3/tl_",file_i,"_", file_l, ".h5")
	smrlb = string("nema3/rlb_",file_i,"_", file_l, ".h5")
	smrlr = string("nema3/rlr_",file_i,"_", file_l, ".h5")
	#smrlkk = string("nema3/rlkk_",file_i,"_", file_l, ".h5")

	JPetalo.write_lors_hdf5(datadir(smtl), mtl)
	JPetalo.write_lors_hdf5(datadir(smrlb), mrlb)
	JPetalo.write_lors_hdf5(datadir(smrlr), mrlr)
	#JPetalo.write_lors_hdf5(datadir(smrlkk), mrlkk)
end

@time makelors()
