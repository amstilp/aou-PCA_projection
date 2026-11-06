version 1.0

workflow cluster_samples {
	input {
        File sample_pcs_file
        File cluster_means_file
        Int samples_per_batch = 10000
	}

	call split_sample_pc_file {
		input:
			sample_pc_file = sample_pcs_file,
			samples_per_batch = samples_per_batch
	}

	scatter (batch_file in split_sample_pc_file.sample_pc_batch_files) {
		call cluster_samples {
            input:
                sample_pc_file = batch_file,
                cluster_means_file = cluster_means_file
        }
	}

    call combine_batches {
        input:
            cluster_batch_files = cluster_samples.cluster_file
    }

    output {
        File cluster_file = combine_batches.cluster_file
    }

	meta {
		author: "Adrienne Stilp"
		email: "amstilp@uw.edu"
		description: "Workflow to cluster samples based on principal components and cluster PC means."
	}
}

task split_sample_pc_file {
    input {
        File sample_pc_file
        Int samples_per_batch = 10000
    }

    command <<<
    echo "Processing ~{sample_pc_file}"
    echo "Number of lines: $(wc -l ~{sample_pc_file})"

    header=$(head -n 1 "~{sample_pc_file}")
    export header
    echo "Header: $header"

    mkdir ./output
    tail -n +2 "~{sample_pc_file}" | \
        split -l "~{samples_per_batch}" \
        -d \
        --additional-suffix=.tsv \
        --filter='{ printf %s\\n "$header"; cat; } >./output/$FILE' - batch_

    ls ./output
    >>>

    output {
        Array[File] sample_pc_batch_files = glob("./output/batch_*.tsv")
    }

    runtime{
         docker: "us-central1-docker.pkg.dev/all-of-us-rw-prod/aou-rw-gar-remote-repo-docker-prod/ubuntu:24.04"
    }
}

task cluster_samples {
    input {
        File sample_pc_file
        File cluster_means_file
        File cluster_function_file = "https://raw.githubusercontent.com/UW-GAC/primed_example_notebooks/refs/heads/main/legacy_project/define_clusters.R"
        Int mem_gb = 8
    }

	command <<<

        R --vanilla << RSCRIPT

        library(data.table)
        library(readr)

        source("~{cluster_function_file}")
        cluster_centers <- read_tsv("~{cluster_means_file}")
        pcs <- fread("~{sample_pc_file}")
        cluster_defs <- define_clusters(pcs, cluster_centers)
        write_tsv(cluster_defs, "clusters.tsv")

        RSCRIPT
	>>>

	output {
		File cluster_file = "clusters.tsv"
	}

	runtime {
		docker: "us-central1-docker.pkg.dev/all-of-us-rw-prod/aou-rw-gar-remote-repo-docker-prod/rocker/tidyverse:4.6.1"
		memory: mem_gb + " GB"
	}
}


task combine_batches {
    input {
        Array[File] cluster_batch_files
    }

    command <<<

        R << RSCRIPT
        library(tidyverse)
        files = str_split("~{sep=' ' cluster_batch_files}", " ")[[1]]
        clusters = lapply(files, read_tsv, show_col_types = FALSE) %>% bind_rows()
        write_tsv(clusters, "clusters.tsv")
        RSCRIPT
    >>>

    output {
        File cluster_file = "clusters.tsv"
    }

    runtime{
         docker: "us-central1-docker.pkg.dev/all-of-us-rw-prod/aou-rw-gar-remote-repo-docker-prod/rocker/tidyverse:4.6.1"
    }
}
