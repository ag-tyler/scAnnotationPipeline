# ==================================================================================================
# Script: 04_utils_caching.R
# Purpose: Collection of functions to cache processed data.
# ==================================================================================================



# --------------------------------------------------------------------------------------------------
# 1. Environment & Packages
# --------------------------------------------------------------------------------------------------


library(docstring)




# --------------------------------------------------------------------------------------------------
# 2. Save, load, delete caches
# --------------------------------------------------------------------------------------------------


setup_cache_dir <- function(dataset_dir_path) {
  #' Set up the cache directory
  #'
  #' Creates a `cache` subdirectory within the specified dataset directory if it does not already exist. 
  #' It safely ignores the command if the directory is already present.
  #'
  #' @param dataset_dir_path Character. The relative path to the parent dataset directory.
  #' @return Character. The absolute file path to the created (or existing) cache directory.
  
  cache_dir_path <- file.path(dataset_dir_path, 'cache')
  dir.create(cache_dir_path, showWarnings = FALSE)
  return(cache_dir_path)
}

cache_save_data <- function(
    data_file, 
    data_file_name, 
    dataset_dir_path, 
    nthreads = 4
    ) {
  #' Save data to the cache
  #'
  #' Serializes and saves an R object to the cache directory using the high-performance `qs2` package.
  #'
  #' @param data_file Any R object. The data or object you want to save to disk.
  #' @param data_file_name Character. The desired filename for the cached object (e.g., "matrix.qs2").
  #' @param dataset_dir_path Character. The relative path to the parent dataset directory.
  #' @param nthreads Numeric. The number of CPU threads to use for compression. Defaults to 4.
  #' @return None. Saves the serialized object to disk.
  
  cache_dir_path <- setup_cache_dir(dataset_dir_path)
  data_file_path <- file.path(cache_dir_path, data_file_name)
  qs2::qs_save(data_file, data_file_path, nthreads = nthreads)
}


cache_load_data <- function(data_file_name, dataset_dir_path, nthreads = 4) {
  #' Load data from the cache
  #'
  #' Reads and deserializes an R object from the cache directory using the `qs2` package.
  #'
  #' @param data_file_name Character. The filename of the cached object to load (e.g., "matrix.qs2").
  #' @param dataset_dir_path Character. The relative path to the parent dataset directory.
  #' @param nthreads Numeric. The number of CPU threads to use for decompression. Defaults to 4.
  #' @return The deserialized R object.
  
  data_file_path <- file.path(setup_cache_dir(dataset_dir_path), data_file_name)
  
  if (!file.exists(data_file_path)) {
    stop(
      "Expected cached file not found: '", data_file_name, "'.\n",
      "This usually means an earlier pipeline step hasn't been run yet for this sample.",
      call. = FALSE
    )
  }
  
  data_file <- qs2::qs_read(data_file_path, nthreads = nthreads)
  return(data_file)
}


cache_check_exists <- function(data_file_name, dataset_dir_path) {
  #' Check if a cached file exists
  #'
  #' Verifies whether a specific data file is already present in the `cache` subdirectory 
  #' of the specified dataset. This is particularly useful for control flow in pipelines 
  #' to skip expensive computations if the data has already been processed and saved.
  #'
  #' @param data_file_name Character. The filename of the cached object to check for (e.g., "matrix.qs2").
  #' @param dataset_dir_path Character. The relative path to the parent dataset directory.
  #' @return Logical. Returns `TRUE` if the file exists on disk, and `FALSE` otherwise.
  
  cache_dir_path <- setup_cache_dir(dataset_dir_path)
  data_file_path <- file.path(cache_dir_path, data_file_name)
  return(file.exists(data_file_path))
}


clear_cache_dir <- function(dataset_dir_path) {
  #' Clear the cache directory
  #'
  #' Deletes all cached files within the `cache` subdirectory of the specified dataset directory.
  #'
  #' @param dataset_dir_path Character. The relative path to the parent dataset directory.
  #' @return None. Modifies the file system by deleting files.
  
  cache_dir_path <- setup_cache_dir(dataset_dir_path)
  unlink(file.path(cache_dir_path, '*'))
}








