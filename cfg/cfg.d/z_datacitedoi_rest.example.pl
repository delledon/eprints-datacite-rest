# DataCite REST integration for EPrints -- example configuration
#
# Copy to an archive-local cfg/cfg.d file and adapt it. Never commit secrets.

$c->{datacitedoi}{eprintdoifield} = "doi";

# Never mint automatically on status transitions.
$c->{datacitedoi}{auto_coin} = 0;
$c->{datacitedoi}{action_coin} = 0;

# Disable the historical MDS write event and CoinDOI screen when this REST
# implementation is active.
$c->{plugins}{"Event::DataCiteEvent"}{params}{disable} = 1;
$c->{plugins}{"Screen::EPrint::Staff::CoinDOI"}{params}{disable} = 1;
$c->{datacitedoi}{apiurl} = undef;

$c->{datacitedoi}{rest_apiurl} = "https://api.datacite.org";

# DOI namespace. The default canonical candidate is:
#   <mint_prefix>/<repoid>/<eprintid>
$c->{datacitedoi}{prefix} = "10.EXAMPLE";
$c->{datacitedoi}{mint_prefix} = "10.EXAMPLE";
$c->{datacitedoi}{repoid} = "repository";
$c->{datacitedoi}{integration_label} = "Example Repository";

# DataCite client relationship expected from authenticated Member API GETs.
$c->{datacitedoi}{client_id} = "consortium.repository";

# Dedicated API-key file. The file content is never committed.
$c->{datacitedoi}{credential_file} =
    "/opt/eprints3/var/credentials/datacite-repository.key";

# DataCite Metadata Schema 4.7.
$c->{datacitedoi}{xmlns} = "http://datacite.org/schema/kernel-4";
$c->{datacitedoi}{schemaLocation} =
    "http://datacite.org/schema/kernel-4 "
    . "https://schema.datacite.org/meta/kernel-4.7/metadata.xsd";

# Only archived records are eligible by default.
$c->{datacitedoi}{eprintstatus}{inbox}    = 0;
$c->{datacitedoi}{eprintstatus}{buffer}   = 0;
$c->{datacitedoi}{eprintstatus}{archive}  = 1;
$c->{datacitedoi}{eprintstatus}{deletion} = 0;

# Choose one mint policy.
$c->{datacitedoi}{mint_all_types} = 0;
$c->{datacitedoi}{typesallowed} = {
    article      => 1,
    book         => 1,
    book_section => 1,
    thesis       => 1,
};

# Exact numeric EPrints user IDs authorised for DataCite writes.
$c->{datacitedoi}{write_userids} = {
    1001 => 1,
};

# Fields containing historical/external identifiers. Any DOI-like value in
# one of these fields is a duplicate barrier.
$c->{datacitedoi}{duplicate_barrier_fields} = [ "id_number" ];

# Optional creator-policy controls used by the generic metadata preflight.
$c->{datacitedoi}{corporate_creator_fields} =
    [ "corp_creators", "corporate_creators" ];
$c->{datacitedoi}{editor_fallback_types} = { book => 1 };

# Mandatory Publisher fallback used by the example mapping.
$c->{datacitedoi}{publisher_fallback} = "Example Repository";

# Optional mapping of local EPrint type => [resourceType, resourceTypeGeneral].
$c->{datacitedoi}{typemap} = {
    article      => [ "Journal Article", "JournalArticle" ],
    book_section => [ "Book Chapter", "BookChapter" ],
    book         => [ "Book", "Book" ],
    thesis       => [ "Thesis", "Dissertation" ],
    monograph    => [ "Monograph", "Text" ],
    conference_item => [ "Conference Paper", "ConferencePaper" ],
    video        => [ "Video", "Audiovisual" ],
    audio        => [ "Audio", "Sound" ],
    dataset      => [ "Dataset", "Dataset" ],
    other        => [ "Other", "Other" ],
};

# -------------------------------------------------------------------------
# Optional custom namespace callbacks.
# -------------------------------------------------------------------------
# Use these when existing managed DOI do not follow <prefix>/<repoid>/<id>.
#
# $c->{datacitedoi}{canonical_doi} = sub {
#     my( $repo, $eprint ) = @_;
#     return "10.EXAMPLE/custom/" . $eprint->id;
# };
#
# $c->{datacitedoi}{managed_doi_eprintid} = sub {
#     my( $repo, $doi ) = @_;
#     return $1 if $doi =~ m{^10\\.EXAMPLE/custom/([0-9]+)$}i;
#     return undef;
# };
#
# A repository may also override the generic metadata preflight:
#
# $c->{datacitedoi}{metadata_preflight} = sub {
#     my( $repo, $eprint ) = @_;
#     return (1, "repository-specific metadata preflight passed");
# };

1;
