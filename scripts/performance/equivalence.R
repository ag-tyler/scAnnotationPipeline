# Development-only comparisons. This directory is not sourced by the app.
perf_numeric_metrics <- function(reference, candidate, tolerance = 0) {
  structure_ok <- identical(dim(reference), dim(candidate)) &&
    identical(dimnames(reference), dimnames(candidate)) &&
    identical(names(reference), names(candidate)) && identical(class(reference), class(candidate)) &&
    identical(typeof(reference), typeof(candidate)) && length(reference) == length(candidate)
  if (!structure_ok) return(list(pass = FALSE, reason = "numeric identity/order/dimensions changed"))
  if (inherits(reference, "sparseMatrix") || inherits(candidate, "sparseMatrix")) {
    if (!inherits(reference, "sparseMatrix") || !inherits(candidate, "sparseMatrix")) {
      return(list(pass = FALSE, reason = "sparse representation changed; adapter review required"))
    }
    a <- methods::as(reference, "dgCMatrix")
    b <- methods::as(candidate, "dgCMatrix")
    if (!identical(a@p, b@p) || !identical(a@i, b@i)) {
      return(list(pass = FALSE, reason = "sparse topology changed"))
    }
    reference <- a@x
    candidate <- b@x
  }
  max_error <- 0
  squared_error <- 0
  finite_count <- 0
  special_ok <- TRUE
  # Bound temporary allocations, including for large saved CNA tables.
  for (start in seq.int(1L, max(1L, length(reference)), by = 1000000L)) {
    if (!length(reference)) break
    index <- seq.int(start, min(length(reference), start + 999999L))
    a <- reference[index]
    b <- candidate[index]
    finite <- is.finite(a) & is.finite(b)
    special_ok <- special_ok && identical(is.na(a), is.na(b)) &&
      identical(is.nan(a), is.nan(b)) && identical(is.infinite(a), is.infinite(b)) &&
      identical(a[is.infinite(a)], b[is.infinite(b)])
    delta <- abs(a[finite] - b[finite])
    if (length(delta)) max_error <- max(max_error, delta)
    squared_error <- squared_error + sum(delta^2)
    finite_count <- finite_count + length(delta)
  }
  list(pass = special_ok && max_error <= tolerance, max_absolute_error = max_error,
    rms_error = if (finite_count) sqrt(squared_error / finite_count) else 0,
    special_values_match = special_ok, tolerance = tolerance)
}

perf_partition_metrics <- function(reference, candidate) {
  if (length(reference) != length(candidate) || !identical(names(reference), names(candidate)) ||
      anyNA(reference) || anyNA(candidate)) {
    return(list(pass = FALSE, reason = "partition cell identity/order or missing values changed"))
  }
  contingency <- table(as.character(reference), as.character(candidate))
  same_membership <- all(rowSums(contingency > 0) == 1L) && all(colSums(contingency > 0) == 1L)
  choose2 <- function(x) x * (x - 1) / 2
  pairs <- choose2(length(reference))
  a <- sum(choose2(rowSums(contingency)))
  b <- sum(choose2(colSums(contingency)))
  expected <- if (pairs) a * b / pairs else 0
  denominator <- (a + b) / 2 - expected
  ari <- if (denominator == 0) as.numeric(same_membership) else
    (sum(choose2(contingency)) - expected) / denominator
  ids_match <- identical(as.character(reference), as.character(candidate))
  list(pass = same_membership && ids_match, same_membership = same_membership,
    adjusted_rand_index = ari, saved_ids_compatible = ids_match)
}

perf_pca_metrics <- function(reference, candidate, contract, exact = FALSE) {
  if (!identical(dim(reference$v), dim(candidate$v)) ||
      !identical(dim(reference$u), dim(candidate$u)) ||
      length(reference$d) != length(candidate$d) ||
      any(!is.finite(c(reference$d, candidate$d, reference$v, candidate$v, reference$u, candidate$u)))) {
    return(list(pass = FALSE, reason = "PCA dimensions/finite values changed"))
  }
  denominator <- pmax(abs(reference$d), .Machine$double.eps)
  relative_error <- max(abs(reference$d - candidate$d) / denominator)
  orthogonal <- function(x) max(abs(crossprod(x) - diag(ncol(x)))) <= 1e-6
  orthogonality_ok <- all(vapply(list(reference$u, reference$v, candidate$u, candidate$v), orthogonal, logical(1)))
  # k-by-k comparison, not a cell-by-cell projection matrix.
  cosine <- svd(crossprod(reference$v, candidate$v), nu = 0, nv = 0)$d
  angle <- max(acos(pmin(1, pmax(0, cosine))))
  exact_match <- identical(reference$d, candidate$d) && identical(reference$v, candidate$v) &&
    identical(reference$u, candidate$u)
  list(pass = orthogonality_ok && if (exact) exact_match else relative_error <= contract$pca_relative_singular_value_error &&
      angle <= contract$pca_max_principal_angle_radians,
    exact_match = exact_match, orthogonality_ok = orthogonality_ok, relative_singular_value_error = relative_error,
    max_principal_angle_radians = angle)
}

perf_embedding_metrics <- function(reference, candidate, contract, exact = FALSE) {
  if (!identical(dim(reference), dim(candidate)) || !identical(dimnames(reference), dimnames(candidate)) ||
      nrow(reference) < 2L || any(!is.finite(reference)) || any(!is.finite(candidate))) {
    return(list(pass = FALSE, reason = "embedding identity/dimensions/finite values changed"))
  }
  a <- sweep(reference, 2, colMeans(reference))
  b <- sweep(candidate, 2, colMeans(candidate))
  rotation <- svd(crossprod(b, a))
  aligned <- b %*% (rotation$u %*% t(rotation$v))
  displacement <- sqrt(rowSums((aligned - a)^2))
  radius <- sqrt(mean(rowSums(a^2)))
  radius <- max(radius, .Machine$double.eps)
  rms <- sqrt(mean(displacement^2)) / radius
  p99 <- unname(stats::quantile(displacement / radius, 0.99))
  k <- min(as.integer(contract$embedding_neighbors), nrow(a) - 1L)
  anchors <- unique(as.integer(round(seq(1, nrow(a), length.out = min(nrow(a), contract$embedding_max_anchors)))))
  neighbors <- function(x, i) {
    distances <- rowSums(sweep(x, 2, x[i, ])^2)
    distances[i] <- Inf
    head(order(distances, seq_along(distances)), k)
  }
  overlap <- vapply(anchors, function(i) length(intersect(neighbors(a, i), neighbors(b, i))) / k, numeric(1))
  exact_match <- identical(reference, candidate)
  list(pass = if (exact) exact_match else rms <= contract$embedding_rms_relative_error &&
      p99 <= contract$embedding_p99_relative_error && mean(overlap) >= contract$embedding_neighborhood_mean_overlap,
    exact_match = exact_match, aligned_rms_relative_error = rms, aligned_p99_relative_error = p99,
    aligned_max_relative_error = max(displacement) / radius,
    neighborhood_mean_overlap = mean(overlap), neighborhood_min_overlap = min(overlap),
    neighborhood_anchors = length(anchors), neighbors = k)
}

perf_table_metrics <- function(reference, candidate, tolerance = 0, cells = FALSE, contract = NULL, exact = FALSE) {
  if (!identical(names(reference), names(candidate)) || !identical(dim(reference), dim(candidate)) ||
      !identical(lapply(reference, class), lapply(candidate, class))) {
    return(list(pass = FALSE, reason = "table schema or dimensions changed"))
  }
  results <- list()
  if (cells && all(c("cell_name", "clust") %in% names(reference))) {
    results$partition <- perf_partition_metrics(setNames(reference$clust, reference$cell_name),
      setNames(candidate$clust, candidate$cell_name))
  }
  embedding <- c("umap1", "umap2")
  if (cells && all(embedding %in% names(reference))) {
    results$embedding <- perf_embedding_metrics(as.matrix(reference[, embedding, drop = FALSE]),
      as.matrix(candidate[, embedding, drop = FALSE]), contract, exact)
  }
  for (name in names(reference)) {
    if (cells && (name == "clust" || name %in% embedding)) next
    a <- reference[[name]]
    b <- candidate[[name]]
    # Numeric identifiers, metadata, ranking keys and assignments remain exact.
    approximate <- is.numeric(a) && name %in% c("cna", "value", "m", "cna_signal", "cna_cor")
    results[[name]] <- if (approximate) perf_numeric_metrics(a, b, tolerance) else
      list(pass = identical(a, b), exact_match = identical(a, b))
  }
  list(pass = all(vapply(results, function(x) isTRUE(x$pass), logical(1))), details = results)
}

perf_compare_object <- function(reference, candidate, kind, contract, policy = "exact") {
  exact <- identical(policy, "exact")
  tolerance <- if (exact) 0 else contract$numeric_max_absolute_error
  switch(kind,
    exact = list(pass = identical(reference, candidate), exact_match = identical(reference, candidate)),
    numeric = perf_numeric_metrics(reference, candidate, tolerance),
    graph = perf_numeric_metrics(reference, candidate, 0),
    pca = perf_pca_metrics(reference, candidate, contract, exact),
    embedding = perf_embedding_metrics(reference, candidate, contract, exact),
    table = perf_table_metrics(as.data.frame(reference), as.data.frame(candidate), tolerance),
    rounded_cna = perf_table_metrics(as.data.frame(reference), as.data.frame(candidate), 0),
    cells = perf_table_metrics(as.data.frame(reference), as.data.frame(candidate), 0,
      cells = TRUE, contract = contract, exact = exact),
    hclust = {
      fields <- c("merge", "height", "order", "labels", "method", "dist.method")
      list(pass = identical(reference[fields], candidate[fields]))
    }, stop("Unknown comparison kind: ", kind))
}

perf_compare_runs <- function(reference_dir, candidate_dir, contract, policy = "exact", common_only = FALSE) {
  if (!policy %in% c("exact", "numerical")) stop("Unknown comparison policy")
  a <- readRDS(file.path(reference_dir, "result.rds"))
  b <- readRDS(file.path(candidate_dir, "result.rds"))
  results <- list()
  results$environment <- list(pass = identical(a$environment, b$environment))
  results$input <- list(pass = identical(a$input_checksum, b$input_checksum))
  results$contract <- list(pass = identical(a$contract_checksum, b$contract_checksum))
  results$warnings <- list(pass = identical(a$warnings, b$warnings))
  keys <- if (common_only) names(a$artifacts)[startsWith(names(a$artifacts), "cache/") |
    names(a$artifacts) %in% c("identity", "cache_controls", "final_assignments")] else
      union(names(a$artifacts), names(b$artifacts))
  results$coverage <- list(pass = (common_only || setequal(names(a$artifacts), names(b$artifacts))) &&
    length(keys) > 0L && identical(a$coverage, b$coverage))
  for (key in keys) {
    left <- a$artifacts[[key]]
    right <- b$artifacts[[key]]
    if (is.null(left) || is.null(right) || !identical(left$kind, right$kind)) {
      results[[key]] <- list(pass = FALSE, reason = "artifact coverage/type changed")
      next
    }
    reference <- readRDS(file.path(reference_dir, left$file))
    candidate <- readRDS(file.path(candidate_dir, right$file))
    results[[key]] <- perf_compare_object(reference, candidate, left$kind, contract, policy)
    rm(reference, candidate)
  }
  list(pass = all(vapply(results, function(x) isTRUE(x$pass), logical(1))),
    policy = policy, results = results)
}
