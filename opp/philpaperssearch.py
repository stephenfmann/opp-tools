import re
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qsl
import sys
try:
    from .debug import debug, debuglevel
    from .util import request_url
except ImportError:
    ## command line usage
    ## SFM: all this stuff seems to be fixing problems with relative imports.
    import os.path
    curpath = os.path.abspath(os.path.dirname(__file__))
    libpath = os.path.join(curpath, os.path.pardir)
    sys.path.insert(0, libpath)
    from opp.debug import debug, debuglevel
    from opp.util import request_url

SEARCH_URL = 'https://philpapers.org/s/{}'

def get_publications(author_name, strict=False):
    """
    fetch list of publications (title, year) for <author_name> from philpapers.
    If <strict>, returns only exact matches for author_name, otherwise allows
    for name variants (e.g., with/without middle initial).
    """
    url = SEARCH_URL.format(author_name)
    debug(3, url)
    status,r = request_url(url)
    if status != 200:
        debug(1, "{} returned status {}".format(url, status))
        return []
    debug(5, r.text)
    if "class='entry'>" not in r.text:
        debug(3, "no results!")
        return []
    
    def name_match_strict(found_name):
        return author_name == found_name

    def name_match_nonstrict(found_name):
        n1parts = author_name.split()
        n2parts = found_name.split()
        # last names must match:
        if n1parts[-1] != n2parts[-1]:
            return False
        # return True if first names also match:
        if n1parts[0] == n2parts[0]:
            return True
        # check if one first name is matching initial:
        if len(n1parts[0]) <= 2 or len(n2parts[0]) <= 2:
            if n1parts[0][0] == n2parts[0][0]:
                return True
        return False

    name_match = name_match_strict if strict else name_match_nonstrict

    results = []
    for recordhtml in r.text.split("class='entry'>")[1:]:
        m = re.search("class='articleTitle[^>]+>([^<]+)</span>", recordhtml)
        if not m:
            continue
        title = m.group(1)
        if len(title) > 255:
           title = title[:251]+'...'
        if title[-1] == '.':
            # philpapers delimits titles that don't end with
            # ?,!,etc. by a dot
            title = title[:-1]
        ms = re.findall("class='name'>([^<]+)</span>", recordhtml)
        authors = [m for m in ms]
        m = re.search('class="pubYear">([^<]+)</span>', recordhtml)
        year = m.group(1) if m and m.group(1).isdigit() else None
        debug(4, '{}: {} ({})'.format(authors, title, year))
        if any(name_match(name) for name in authors):
            debug(4, 'author matches')
            results.append((title, year))
        else:
            debug(4, 'no author match')

    return results


def get_metadata_from_id(doc_id):
    """
    Call PhilPapers to get metadata from the doc_id.
    
    Format of the URL to call is 
    "https://philpapers.org/oai.pl?verb=GetRecord&identifier={doc_id}"

    Parameters
    ----------
    doc_id : str
        PhilPapers internal document identifier e.g. 'REIRPI-2'.

    Returns
    -------
    doc_metadata : dict
        Basic metadata about the document from the returned XML.

    """
    
    ## 1. GET XML
    ## Get the URL to call
    url_oai = f"https://philpapers.org/oai.pl?verb=GetRecord&identifier={doc_id}"
    
    ## Make the request
    http_status_code, r = request_url(url_oai)
    
    ## Check code
    assert http_status_code == 200 # TODO how to do this properly?
    
    ## 2. GET METADATA FROM XML
    ## First use beautiful soup to parse the XML.
    soup = BeautifulSoup(r.content, features="xml")
    
    ## Now get the title and creators of the document from the parsed document.
    title   = soup.find("dc:title").text
    authors_list = soup.find_all("dc:creator")
    
    ## Get author names into a format opp-tools expects
    authors = ""
    for author in authors_list:
        
        ## Philpapers lists "Lastname, Firstname" while opp-tools expects "Firstname Lastname".
        name_list = author.text.split(", ")
        
        ## name_list is [Lastname, Firstnames]
        author_name = f"{name_list[-1]} {name_list[0]}"
        
        ## Add to authors list
        authors += f"{author_name}, "
    
    ## Remove final comma and space
    if len(authors) > 2:
        authors = authors[:-2]
    
    ## Create the metadata dict
    doc_metadata = {
        "title"     : title,
        "authors"   : authors
        }
    
    return doc_metadata

def philpapers_doc_id_from_url(url):
    """
    Get the philpapers "internal identifier" of a document from its url.
    E.g. from "https://philpapers.org/archive/REIRPI-2.pdf" should return "REIRPI-2".

    Parameters
    ----------
    url : str
        URL of the document at PhilPapers.

    Returns
    -------
    doc_id : str
        Philpapers ID of document.

    """
    
    ## First check if the ID is in the url string parameters
    ## Split the url into protocol, domain, location, [something], parameters, [something]
    url_components = list(urlparse(url))
    
    ## If there is a parameters entry...
    if len(url_components) >= 5:
        
        ## ...split the parameters into a dict.
        url_params_dict = dict(parse_qsl(url_components[4]))
        
        ## If there is an ID param, return it now.
        if "id" in url_params_dict: return url_params_dict["id"]
            
    ## Otherwise, try and get it directly
    
    ## Define the search regex
    ## Get everything between the final forward-slash and the ".pdf"
    regex_philpapers_doc_id = ".*/(.*)\.pdf"
    
    ## Apply the regex to the url
    re_search = re.search(regex_philpapers_doc_id,url)
    
    ## Was the pattern found?
    if re_search is None: return False
    
    doc_id = re_search.group(1)
    
    return doc_id

        
if __name__ == "__main__":

    # for testing and debugging
    import argparse
    import logging
    logger = logging.getLogger('opp')
    logger.setLevel(logging.DEBUG)
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.DEBUG)
    logger.addHandler(ch)

    ap = argparse.ArgumentParser()
    ap.add_argument('-v', '--verbose', action='store_true', help='turn on debugging output')
    ap.add_argument('name')
    args = ap.parse_args()
    
    if args.verbose:
        debuglevel(5)

    pubs = get_publications(args.name)
    print('{} publications'.format(len(pubs)))
    for (t,y) in pubs:
        print('{} ({})'.format(t,y))
        
