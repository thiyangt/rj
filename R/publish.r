#' Publish an article to online first.
#'
#' After running this, you'll need to update both the article and 
#' the web repository.
#'
#' @export
#' @importFrom tools texi2pdf
#' @importFrom yaml yaml.load_file
#' @param article article id
#' @param home Location of the articles directory
publish <- function(article, home = getwd()) {
  article <- as.article(article)

  # Make sure we're in the right place
  if (basename(home) != "articles") {
    stop("Publish should be run from articles directory", call. = FALSE)
  }
  web_path <- normalizePath("../rjournal.github.io", mustWork = TRUE)
  share_path <- normalizePath("../share", mustWork = TRUE)
  if (!("accepted" %in% sapply(seq(along=article$status),
    function(i) article$status[[i]][["status"]]))) stop("not yet accepted")
  if (!("style checked" %in% sapply(seq(along=article$status),
    function(i) article$status[[i]][["status"]]))) stop("not yet style checked")

  message("Publishing ", format(article$id))
  # Build latex and copy to new home
  build_latex(article, share_path)
  if (empty(article$slug)) {
    names <- unlist(lapply(article$authors, "[[", "name"))
    slug <- make_slug(names)
  } else {
    slug <- article$slug
  }

  from <- file.path(article$path, "RJwrapper.pdf")
  to <- file.path(web_path, "archive", "accepted", paste0(slug, ".pdf"))
  file.copy(from, to, overwrite = TRUE)
  message("Creating ", basename(to))

  article$slug <- slug
  article <- update_status(article, "online")
  


  ## Make yaml
  yaml_path <- file.path(web_path, "_config.yml")
  message("Updating ", yaml_path)
  config <- yaml.load_file(yaml_path)
  config$issues[[1L]]$articles <- c(config$issues[[1L]]$articles,
                                    list(online_metadata_for_article(article)))
  writeLines(as.yaml(config), yaml_path)
  
  message("Remember to check changes into git")
  invisible(TRUE)
}

get_md_from_pdf <- function(from)
{
   toc <- pdftools::pdf_toc(from)
   title <- toc$children[[1L]]$title
   text <- pdftools::pdf_text(from)
   t1s <- t1s <- strsplit(gsub("           ", "", text[1]), "\\n")[[1L]]
   abs_ <- grep("^Abstract", t1s)
   aut0 <- paste(t1s[grep("^by", t1s):(abs_-1L)], collapse=" ")
   author <- substring(aut0, 4, nchar(aut0))
   abs0 <- paste(t1s[abs_:(grep(paste0("^", toc$children[[1L]]$children[[1L]]$title), t1s)-1L)], collapse=" ")
   abstract <- substring(abs0, 10, nchar(abs0))
   list(author=author, title=title, abstract=abstract)
}

#' Build article from LaTeX
#' 
#' @export
build_latex <- function(article,
                        share_path = normalizePath("../share", mustWork = TRUE),
                        clean = TRUE)
{
  article <- as.article(article)
  stopifnot(file.exists(share_path))
  
  # Check RJournal.sty does not exist
  sty_path <- file.path(article$path, "RJournal.sty")
  if (file.exists(sty_path)) {
    stop("Article contains RJournal style file", call. = FALSE)
  }

  # Build latex
  in_dir(article$path,
    texi2pdf("RJwrapper.tex", texinputs = share_path, clean = clean)
  )
}

#' Generate metadata needed for website.
#' 
#' @importFrom yaml as.yaml
#' @export
online_metadata <- function() {
  articles <- accepted_articles()
  articles <- Filter(function(x) !empty(x$slug), articles)
  lapply(articles, online_metadata_for_article)
}

online_metadata_for_article <- function(x) {
#    names <- vapply(x$authors, function(x) {
#                        format(as.person(x),
#                               include = c("given", "family"))[[1]]
#                    }, FUN.VALUE = character(1L))
    from <- file.path(x$path, "RJwrapper.pdf")
    pdf_list <- get_md_from_pdf(from)
    list(
        title = pdf_list$title,
        slug = x$slug,
        author = pdf_list$author,
        abstract = pdf_list$abstract,
        acknowledged = format(x$status[[2L]]$date),
        online = format(Sys.Date())
        )
}

#' @S3method print catout
print.catout <- function(x, ...) cat(x, "\n", sep = "")

make_slug <- function(names) {
  people <- as.person(names)
  family <- unlist(lapply(people, function(x) x[[1]]$family))
  if (length(family) > 3) {
    family <- c(family[1:3], "et-al")
  }

  family <- iconv(family, to = "ASCII//translit")
  family <- gsub("[^A-Za-z]", "", family)
  tolower(paste0(family, collapse = "-"))
}

bundle <- function(article, dest_path) {
  article <- as.article(article)
  dest <- file.path(dest_path, paste0(format(article$id), ".zip"))

  # Check confidential files are present, but don't include in zip file
  files <- dir(article$path)
  conf <- c("DESCRIPTION", "correspondence")

  if (length(intersect(files, conf)) != 2) {
    stop(paste(setdiff(conf, files), collapse = ", "), "not found in ", article$path)
  }
  files <- setdiff(files, conf)

  # Create zip file
  in_dir(article$path, zip(dest, files))
}

