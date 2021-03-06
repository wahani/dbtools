#' SQL Query Objects
#'
#' Data types to represent SQL queries. It should not be necessary to use
#' SingleQuery and SingleQueryList interactively. \code{Query} is the generic
#' user interface to generate SQL queries and is based on text parsing.
#'
#' @param .x (character | connection) A character or connection containing a
#'   query.
#' @param ... Parameters to be substituted in .x
#' @param .data (list)
#' @param .envir (environment) Should be left with the default. Sets the
#'   environment in which to evaluate code chunks in queries.
#' @param checkSemicolon (logical) Should be left with the default. Set to
#'   false only in case you want to allow for semicolons within the query.
#' @param keepComments (logical) In most cases it is safe(er) to remove comments
#'   from a query. When you want to keep them set the argument to \code{TRUE}.
#'   This only applies when \code{.x} is a file.
#'
#' @rdname queries
#'
#' @details
#'
#' \code{SingleQuery} inherits from \code{character} and represents a single
#' query.
#'
#' \code{SingleQueryList} inherits from \code{list} and represents a list of
#' single queries. It can be constructed with a list of character values.
#'
#' @examples
#' query1 <- "SELECT {{ varName }} FROM {{ tableName }} WHERE primaryKey = {{ id }};"
#' query2 <- "SHOW TABLES;"
#'
#' Query(query1, varName = "someVar", tableName = "someTable", .data = list(id = 1:2))
#'
#' tmpFile <- tempfile()
#' writeLines(c(query1, query2), tmpFile)
#' Query(file(tmpFile))
#' @export
Query <- function(.x, ..., .data = NULL, .envir = parent.frame(),
                  checkSemicolon = TRUE, keepComments = FALSE) {

  query <- queryRead(.x, keepComments)
  query <- queryEvalTemplate(query, .data, .envir = .envir, ...)

  queryConst(query, checkSemicolon = checkSemicolon)

}

queryRead(x, ...) %g% x

queryRead(x ~ connection, keepComments, ...) %m% {
  on.exit(close(x))

  query <- readLines(x)
  query <- if (keepComments) query else sub("(-- .*)|(#.*)", "", query)
  query <- query[query != ""]
  query <- paste(query, collapse = "\n")
  query <- if (keepComments) query else gsub("(\\\n)?/\\*.*?\\*/", "", query)
  query <- unlist(strsplit(query, ";"))
  query <- paste0(query, ";")
  query <- sub("^\\n+", "", query)
  query

}

queryEvalTemplate(x, .data, ...) %g% x

queryEvalTemplate(x ~ list, .data ~ NULL, ...) %m% {
  x <- lapply(x, as.character)
  x <- lapply(x, tmpl, ...)
  x <- lapply(x, as.character)
  x
}

queryEvalTemplate(x ~ character, .data ~ ANY, ...) %m% {
  queryEvalTemplate(as.list(x), .data, ...)
}

queryEvalTemplate(x ~ list, .data ~ data.frame, ...) %m% {
  queryEvalTemplate(x, as.list(.data), ...)
}

queryEvalTemplate(x ~ list, .data ~ list, ...) %m% {

  localQueryEval <- function(...) {
    do.call(
      queryEvalTemplate,
      c(list(x = x, .data = NULL), fixedDots, ...)
    )
  }

  fixedDots <- list(...)

  do.call(Map, c(list(f = localQueryEval), .data))

}

queryConst <- function(x, checkSemicolon) {
  if (length(x) == 1) SingleQuery(x[[1]], checkSemicolon = checkSemicolon)
  else SingleQueryList(as.list(x), checkSemicolon = checkSemicolon)
}

#' @exportClass SingleQuery
#' @rdname queries
character : SingleQuery(checkSemicolon = TRUE) %type% {
  assert_that(
    is.scalar(.Object),
    grepl(";$", .Object),
    if (.Object@checkSemicolon)
      length(unlist(strsplit(.Object, ";"))) == 1 else TRUE
  )
  .Object
}

SingleQuery <- function(..., checkSemicolon = TRUE) new(
  'SingleQuery', checkSemicolon = checkSemicolon, ...
)

#' @exportClass SingleQueryList
#' @rdname queries
list : SingleQueryList(checkSemicolon = TRUE) %type% {
  S3Part(.Object) <- lapply(.Object, SingleQuery, checkSemicolon = .Object@checkSemicolon)
  .Object
}

SingleQueryList <- function(..., checkSemicolon = TRUE) new(
  'SingleQueryList', checkSemicolon = checkSemicolon, ...
)

show(object ~ SingleQuery) %m% {
  cat("Query:\n", S3Part(object, TRUE), "\n\n", sep = "")
  invisible(object)
}

show(object ~ SingleQueryList) %m% {
  lapply(object, show)
  invisible(object)
}
