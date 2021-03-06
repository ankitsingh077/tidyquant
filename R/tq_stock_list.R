#' Get all stocks in a stock index or stock exchange in `tibble` format
#'
#' @param x A single character string, a character vector or tibble representing a
#' single stock index or multiple stock indexes.
#' @param use_fallback A boolean that can be used to return a fallback data set
#' last downloaded when the package was updated. Useful if the website is down.
#' Set to `FALSE` by default.
#'
#' @return Returns data in the form of a `tibble` object.
#'
#' @details
#' `tq_index()` returns the stock symbol, company name, weight, and sector of every stock
#' in an index. The source is
#' \href{https://us.spdrs.com/en/product/}{www.us.spdrs.com}.
#'
#' `tq_index_options()` returns a list of stock indexes you can
#' choose from.
#'
#' `tq_exchange()` returns the stock symbol, company, last sale price,
#' market capitalization, sector and industry of every stock
#' in an exchange. Three stock exchanges are available (AMEX, NASDAQ, and NYSE).
#'
#' `tq_exchange_options()` returns a list of stock exchanges you can
#' choose from. The options are AMEX, NASDAQ and NYSE.
#'
#' @seealso
#' [tq_get()] to get stock prices, financials, key stats, etc using the stock symbols.
#'
#' @rdname tq_stock_list
#'
#' @export
#'
#' @examples
#' # Load libraries
#' library(tidyquant)
#'
#' # Get the list of stock index options
#' tq_index_options()
#'
#' # Get all stock symbols in a stock index
#' \dontrun{
#' tq_index("DOW")
#' }
#'
#' # Get the list of stock exchange options
#' tq_exchange_options()
#'
#' # Get all stocks in a stock exchange
#' \dontrun{
#' tq_exchange("NYSE")
#' }


# tq_index -----

#' @rdname tq_stock_list
#' @export
tq_index <- function(x, use_fallback = FALSE) {

    # Clean index name
    x <- clean_index(x)

    # Verify index
    verified <- verify_index(x)

    # If not a verified index, error
    if(!verified$is_verified) {
        warning(verified$err)
        return(tibble::tibble())
    }

    # Use fallback if requested
    if(use_fallback) return(index_fallback(x))

    # Convert index name to SPDR ETF name
    x_spdr <- spdr_mapper(x)

    # Download
    dload <- index_download(x_spdr, index_name = x)

    # Report download errors
    if(!is.null(dload$err)) {
        warning(dload$err)
        return(tibble::tibble())
    }

    # Clean holdings
    df <- clean_holdings(dload$df)

    df
}

# tq_exchange ----

#' @rdname tq_stock_list
#' @export
tq_exchange <- function(x) {

    # Reformat x
    x <- stringr::str_to_lower(x) %>%
        stringr::str_trim(side = "both") %>%
        stringr::str_replace_all("[[:punct:]]", "")

    # Check if x is a valid exchange
    exchange_list <- tq_exchange_options() %>%
        stringr::str_to_lower()
    if (!(x %in% c(exchange_list))) {
        err <- paste0("Error: x must be a character string in the form of a valid exchange.",
                      " The following are valid options:\n",
                      stringr::str_c(tq_exchange_options(), collapse = ", ")
        )
        stop(err)
    }

    tryCatch({

        message("Getting data...\n")

        # Download File
        tmp <- tempfile()
        # base_path_1 <- "http://www.nasdaq.com/screening/companies-by-name.aspx?letter=0&exchange="
        base_path_1 <- "https://old.nasdaq.com/screening/companies-by-name.aspx?letter=0&exchange="
        base_path_2 <- "&render=download"
        url <- paste0(base_path_1, x, base_path_2)
        download.file(url, destfile = tmp, quiet = TRUE)

        # Read data
        exchange_raw <- suppressMessages(
            suppressWarnings(
                read.csv(tmp, na.strings = c("", "NA", "N/A", "<NA>", "n/a"), stringsAsFactors = FALSE)[1:7]
            )
        )

        # Unlink tmp
        unlink(tmp)

        # Format df
        exchange <- exchange_raw %>%
            dplyr::mutate_if(is.character, stringr::str_trim) %>%
            dplyr::as_tibble() %>%
            dplyr::rename(
                symbol = Symbol,
                company = Name,
                last.sale.price = LastSale,
                market.cap = MarketCap,
                ipo.year = IPOyear,
                sector = Sector
            ) %>%
            dplyr::mutate(
                symbol = as.character(symbol),
                company = as.character(company),
                last.sale.price = as.numeric(last.sale.price),
                market.cap = as.character(market.cap),
                ipo.year = as.numeric(ipo.year),
                sector = as.character(sector),
                industry = as.character(industry)
            )

        return(exchange)

    }, error = function(e) {

        warn <- paste0("Error at ", x, " during call to tq_exchange.")
        warning(warn)
        return(NA) # Return NA on error

    })

}

#' @rdname tq_stock_list
#' @export
tq_index_options <- function() {
    c(
      "DOW",
      "DOWGLOBAL",
      "SP400",
      "SP500",
      "SP600"
      )
}


#' @rdname tq_stock_list
#' @export
tq_exchange_options <- function() {
    c("AMEX", "NASDAQ", "NYSE")
}

# Utility ----------------------------------------------------------------------------------------------------

# Casing and punctuation
clean_index <- function(x) {

    # Capitalize, trim space, and remove any punctuation
    stringr::str_to_upper(x) %>%
        stringr::str_trim(side = "both") %>%
        stringr::str_replace_all("[[:punct:]]", "")
}

# Verify index is of the right form
verify_index <- function(x) {

    # Setup with initial values
    verified <- list(is_verified = FALSE, err = "")

    if(!(x %in% tq_index_options())) {

        verified$err <- paste0(x, " must be a character string in the form of a valid index. ",
                               "The following are valid options:\n",
                               stringr::str_c(tq_index_options(), collapse = ", "))
    } else {
        verified$is_verified <- TRUE
    }

    verified
}

# Map the index to the SPDR ETF name
spdr_mapper <- function(x) {

    switch(x,
           RUSSELL1000 = "ONEK",
           RUSSELL2000 = "TWOK",
           RUSSELL3000 = "THRK",
           DOW         = "DIA",
           DOWGLOBAL   = "DGT",
           SP400       = "MDY",
           SP500       = "SPY",
           SP600       = "SLY",
           SP1000      = "SMD"
           )
}

# Download the index data from SPDR
index_download <- function(x, index_name) {

    # Contruct download link
    #     OLD (< 2019-12-15): https://us.spdrs.com/site-content/xls/SPY_All_Holdings.xls
    #     NEW (> 2019-12-15) https://www.ssga.com/us/en/institutional/etfs/library-content/products/fund-data/etfs/us/holdings-daily-us-en-spy.xlsx
    # spdr_link <- paste0("https://us.spdrs.com/site-content/xls/", x, "_All_Holdings.xls")
    spdr_link <- paste0("https://www.ssga.com/us/en/institutional/etfs/library-content/products/fund-data/etfs/us/holdings-daily-us-en-", tolower(x), ".xlsx")

    # Results container
    res <- list(df = NULL, err = NULL)

    # Message
    message("Getting holdings for ", index_name)

    # Download quietly
    tryCatch({

        # Download to disk, force as a xlsx
        httr::GET(spdr_link, httr::write_disk(tf <- tempfile(fileext = ".xlsx")))

        # Read the xls file
        suppressMessages({
            # res$df <- gdata::read.xls(tf, skip = 3, stringsAsFactors = FALSE)
            # res$df <- readxl::read_xls(tf, skip = 3)
            # wb     <- XLConnect::loadWorkbook(filename = tf)
            # res$df <- XLConnect::readWorksheet(wb, sheet = 1, startRow = 4)

            res$df <- readxl::read_xlsx(tf, skip = 3)
        })

        # Release temp file
        unlink(tf)

        return(res)

    }, error = function(e) {

        # On error, catch it and return
        res$err <- paste0("Error at ", index_name, " during download. \n", e)

        return(res)

    })
}

# Series of commands to clean the results from SPDR
clean_holdings <- function(x) {

    # Identify the last row of data
    last_row <- which(is.na(x[["Weight"]]))[1] - 1

    ret <- x %>%

        # Subset rows with data
        dplyr::slice(1:last_row) %>%

        # Remove rows of cash
        dplyr::filter(Sector != "Unassigned") %>%

        # Type convert (bad data has been removed)
        # as.is = TRUE to prevent character -> factor
        purrr::modify(~type.convert(., as.is = TRUE)) %>%

        # Reweight
        dplyr::mutate(Weight = Weight / sum(Weight))

    # Rename
    names(ret)[1:2] <- c("company", "symbol")
    names(ret) <- names(ret) %>%
        stringr::str_to_lower() %>%
        stringr::str_replace_all(" ", "_")

    # Reorder
    ret <- ret %>% dplyr::select(symbol, company, dplyr::everything())

    return(ret)
}

# Return fallback data if necessary
index_fallback <- function(x) {

    # Date of last download
    date.dload <- stock_indexes %>%
        dplyr::filter(index.option == x) %>%
        dplyr::pull(date.downloaded) %>%
        utils::head(1)

    # Date message
    message(paste0("Using fallback dataset last downloaded ",
                   date.dload[[1]]), ".")

    # Unnest the specific index
    stock_index <- stock_indexes %>%
        dplyr::filter(index.option == x) %>%
        dplyr::select(index.components) %>%
        tidyr::unnest(cols = index.components)

    stock_index
}
