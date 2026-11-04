version 1.0

task identifyColumns {
	input {
		File ref_variants
		String id_column = "ID"
	}

	Int disk_size = ceil(2*(size(ref_variants, "GB"))) + 10

	command <<<
		Rscript -e "\
		dat <- readr::read_tsv('~{ref_variants}', comment = '##', n_max=100); \
		if (ncol(dat) == 1) id_col <- 1 else id_col <- which(names(dat) == '~{id_column}'); \
		system(paste('cut -f', id_col, '~{ref_variants} > variant_ids.txt')); \
		"
	>>>

	output {
		File id_file = "variant_ids.txt"
	}

	runtime {
		docker: "us-central1-docker.pkg.dev/all-of-us-rw-prod/aou-rw-gar-remote-repo-docker-prod/rocker/tidyverse:4.6.1"
		disks: "local-disk " + disk_size + " SSD"
	}
}


task mergeFiles {
	input {
		Array[File] bed
		Array[File] bim
		Array[File] fam
		Boolean rm_dup = true
		String output_chr = "chrM"
		Int mem_gb = 16
	}

	Int disk_size = ceil(3*(size(bed, "GB") + size(bim, "GB") + size(fam, "GB"))) + 10

	command <<<
		set -e -o pipefail

		# merge plink files
		cat ~{write_lines(bed)} | sed 's/\.bed$//' > bfile.txt
		plink2 --pmerge-list bfile.txt bfile \
			--memory ~{mem_gb *  512} \
			--merge-max-allele-ct 2 \
			--out tmp
		plink2 --pfile tmp \
			--memory ~{mem_gb *  512} \
			--output-chr ~{output_chr} \
			--set-all-var-ids @:#:\$r:\$a \
			--make-bed --out merged \
			~{true="--rm-dup exclude-all" false="" rm_dup}
	>>>

	output {
		File out_bed = "merged.bed"
		File out_bim = "merged.bim"
		File out_fam = "merged.fam"
	}

	runtime {
		docker: "us-central1-docker.pkg.dev/all-of-us-rw-prod/aou-rw-gar-remote-repo-docker-prod/rtibiocloud/plink:v2.0.0-a.6.15_18fccba"
		disks: "local-disk " + disk_size + " SSD"
		memory: mem_gb + " GB"
	}
}
