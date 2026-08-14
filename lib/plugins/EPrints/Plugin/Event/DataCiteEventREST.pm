package EPrints::Plugin::Event::DataCiteEventREST;

use strict;
use warnings;

use EPrints::Plugin::Event;

use JSON::PP qw( decode_json encode_json );
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64 encode_base64 );
use Encode qw( encode );

our @ISA = qw( EPrints::Plugin::Event );


############################################################
# DOI normalisation
############################################################

sub _normalise_doi
{
    my( $doi ) = @_;

    return "" unless defined $doi;

    $doi =~ s/^\s+//;
    $doi =~ s/\s+$//;

    $doi =~ s/^doi:\s*//i;
    $doi =~ s{^https?://(?:dx\.)?doi\.org/}{}i;

    $doi =~ s/^\s+//;
    $doi =~ s/\s+$//;

    return $doi;
}


############################################################
# Detect a DOI-like identifier in a historical/external identifier field.
#
# This is deliberately conservative:
# any DOI-looking identifier is a duplicate barrier.
############################################################

sub _extract_doi_like
{
    my( $value ) = @_;

    return "" unless defined $value;

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return "" if $value eq "";

    #
    # First try the whole value. This covers:
    #   10.x/...
    #   doi:10.x/...
    #   https://doi.org/10.x/...
    #   http://dx.doi.org/10.x/...
    #
    my $whole = _normalise_doi( $value );

    if(
        $whole =~ /^10\.[0-9]{4,9}\/\S+$/i
    )
    {
        return $whole;
    }

    #
    # Otherwise detect a DOI embedded in bibliographic text.
    #
    if(
        $value =~
        m{(10\.[0-9]{4,9}/[^\s<>"']+)}i
    )
    {
        my $doi = $1;

        #
        # Remove common sentence punctuation only.
        #
        $doi =~ s/[.,;]+$//;

        return _normalise_doi( $doi );
    }

    return "";
}


############################################################
# Repository-policy helpers
############################################################

sub _integration_label
{
    my( $self ) = @_;

    my $repository = $self->repository();
    return "repository" unless defined $repository;

    return $repository->get_conf("datacitedoi", "integration_label")
        || $repository->get_conf("datacitedoi", "repoid")
        || "repository";
}

sub _doi_field
{
    my( $self ) = @_;

    my $repository = $self->repository();
    return "doi" unless defined $repository;

    return $repository->get_conf("datacitedoi", "eprintdoifield")
        || "doi";
}

# Return the eprintid encoded by a managed DOI, or undef when the DOI is
# outside this repository's managed namespace. A repository may provide a
# CODE callback in datacitedoi.managed_doi_eprintid for legacy namespaces.
sub _managed_doi_eprintid
{
    my( $self, $doi ) = @_;

    my $repository = $self->repository();
    return undef unless defined $repository;

    $doi = _normalise_doi($doi);
    return undef if $doi eq "";

    my $callback =
        $repository->get_conf("datacitedoi", "managed_doi_eprintid");

    if( ref($callback) eq "CODE" )
    {
        my $id = $callback->($repository, $doi);
        return $id if defined $id && $id =~ /^[0-9]+$/;
        return undef;
    }

    my $prefix = $repository->get_conf("datacitedoi", "prefix") || "";
    my $repoid = $repository->get_conf("datacitedoi", "repoid") || "";

    return undef if $prefix eq "" || $repoid eq "";

    return $1
        if $doi =~ /^\Q$prefix\E\/\Q$repoid\E\/([0-9]+)$/i;

    return undef;
}

# Calculate the canonical candidate DOI. Repositories with a different suffix
# policy may provide datacitedoi.canonical_doi as a CODE callback.
sub _canonical_doi_candidate
{
    my( $self, $dataobj ) = @_;

    my $repository = $self->repository();
    return "" unless defined $repository && defined $dataobj;

    my $callback =
        $repository->get_conf("datacitedoi", "canonical_doi");

    if( ref($callback) eq "CODE" )
    {
        return _normalise_doi($callback->($repository, $dataobj) || "");
    }

    my $prefix =
        $repository->get_conf("datacitedoi", "mint_prefix")
        || $repository->get_conf("datacitedoi", "prefix")
        || "";

    my $repoid = $repository->get_conf("datacitedoi", "repoid") || "";

    return "" if $prefix eq "" || $repoid eq "";

    return $prefix . "/" . $repoid . "/" . $dataobj->id;
}

sub _duplicate_barrier_fields
{
    my( $self ) = @_;

    my $repository = $self->repository();
    return [ "id_number" ] unless defined $repository;

    my $fields =
        $repository->get_conf("datacitedoi", "duplicate_barrier_fields");

    return $fields if ref($fields) eq "ARRAY";
    return [ "id_number" ];
}

sub _mint_type_allowed
{
    my( $self, $dataobj ) = @_;

    my $repository = $self->repository();
    return 0 unless defined $repository && defined $dataobj;

    return 1 if $repository->get_conf("datacitedoi", "mint_all_types");

    my $type = $dataobj->exists_and_set("type")
        ? ($dataobj->get_value("type") || "")
        : "";

    my $allowed = $repository->get_conf("datacitedoi", "typesallowed");

    return 1
        if ref($allowed) eq "HASH"
        && exists $allowed->{$type}
        && $allowed->{$type};

    return 0;
}

############################################################
# Mandatory local metadata preflight.
#
# A repository may override this with a CODE callback in
# datacitedoi.metadata_preflight. The default deliberately checks only
# broadly standard EPrints fields; the exporter remains the final authority
# and fails closed if a mandatory DataCite element cannot be produced.
############################################################

sub _metadata_preflight
{
    my( $self, $dataobj ) = @_;

    return (0, "missing data object") unless defined $dataobj;

    my $repository = $self->repository();
    return (0, "missing repository") unless defined $repository;

    my $callback =
        $repository->get_conf("datacitedoi", "metadata_preflight");

    if( ref($callback) eq "CODE" )
    {
        return $callback->($repository, $dataobj);
    }

    my @problems;

    my $type = $dataobj->exists_and_set("type")
        ? ($dataobj->get_value("type") || "") : "";
    $type =~ s/^\s+|\s+$//g;
    push @problems, "missing type" if $type eq "";

    my $title = $dataobj->exists_and_set("title")
        ? ($dataobj->get_value("title") || "") : "";
    push @problems, "missing title" unless $title =~ /\S/;

    my $date = $dataobj->exists_and_set("date")
        ? ($dataobj->get_value("date") || "") : "";
    push @problems, "missing valid publication year"
        unless $date =~ /^[0-9]{4}(?:\b|-)/;

    my $has_creator = 0;

    if( $dataobj->exists_and_set("creators_name") )
    {
        my $names = $dataobj->get_value("creators_name");
        if( ref($names) eq "ARRAY" )
        {
            for my $name (@$names)
            {
                next unless ref($name) eq "HASH";
                if( ($name->{family} || "") =~ /\S/
                    || ($name->{given} || "") =~ /\S/ )
                {
                    $has_creator = 1;
                    last;
                }
            }
        }
    }

    my $corp_fields =
        $repository->get_conf("datacitedoi", "corporate_creator_fields");
    $corp_fields = [ "corp_creators", "corporate_creators" ]
        unless ref($corp_fields) eq "ARRAY";

    unless( $has_creator )
    {
        FIELD:
        for my $field (@$corp_fields)
        {
            next unless $dataobj->dataset->has_field($field);
            next unless $dataobj->exists_and_set($field);

            my $values = $dataobj->get_value($field);
            $values = [ $values ] unless ref($values) eq "ARRAY";

            for my $value (@$values)
            {
                if( defined $value && $value =~ /\S/ )
                {
                    $has_creator = 1;
                    last FIELD;
                }
            }
        }
    }

    my $editor_types =
        $repository->get_conf("datacitedoi", "editor_fallback_types");
    $editor_types = { book => 1 } unless ref($editor_types) eq "HASH";

    if( !$has_creator && $editor_types->{$type}
        && $dataobj->exists_and_set("editors_name") )
    {
        my $names = $dataobj->get_value("editors_name");
        if( ref($names) eq "ARRAY" )
        {
            for my $name (@$names)
            {
                next unless ref($name) eq "HASH";
                if( ($name->{family} || "") =~ /\S/
                    || ($name->{given} || "") =~ /\S/ )
                {
                    $has_creator = 1;
                    last;
                }
            }
        }
    }

    push @problems, "missing usable creator" unless $has_creator;

    return (0, join("; ", @problems)) if @problems;
    return (1, "mandatory local metadata are present");
}

############################################################
# Local classification -- NO NETWORK ACCESS.
############################################################

sub classify_datacite
{
    my( $self, $dataobj ) = @_;

    my $repository = $self->repository();
    return ("BLOCK", "", "missing repository") unless defined $repository;
    return ("BLOCK", "", "missing data object") unless defined $dataobj;

    my $id = $dataobj->id;
    my $status = $dataobj->get_value("eprint_status") || "";

    my $enabled =
        $repository->get_conf("datacitedoi", "eprintstatus", $status);

    return ("BLOCK", "", "eprint status '$status' is not enabled for DataCite")
        unless $enabled;

    my $field = $self->_doi_field();
    my $doi = "";

    if( $dataobj->dataset->has_field($field)
        && $dataobj->exists_and_set($field) )
    {
        $doi = _normalise_doi($dataobj->get_value($field));
    }

    if( $doi ne "" )
    {
        my $doi_id = $self->_managed_doi_eprintid($doi);

        unless( defined $doi_id )
        {
            return (
                "BLOCK_UNMANAGED_DOI_FIELD",
                $doi,
                "dedicated DOI field contains a DOI outside the configured managed namespace"
            );
        }

        if( $doi_id != $id )
        {
            return (
                "BLOCK_WRONG_MANAGED_IDENTIFIER",
                $doi,
                "managed repository DOI contains eprintid $doi_id but record is $id"
            );
        }

        my( $metadata_ok, $metadata_reason ) =
            $self->_metadata_preflight($dataobj);

        return ("BLOCK_METADATA", $doi, $metadata_reason)
            unless $metadata_ok;

        return (
            "UPDATE",
            $doi,
            "dedicated DOI field contains a managed DOI for this eprint"
        );
    }

    # Any DOI-like identifier in a configured historical/external field is a
    # duplicate barrier. A canonical-looking managed DOI requires explicit
    # remote reconciliation rather than a second mint.
    for my $barrier_field (@{ $self->_duplicate_barrier_fields() })
    {
        next unless $dataobj->dataset->has_field($barrier_field);
        next unless $dataobj->exists_and_set($barrier_field);

        my $value = $dataobj->get_value($barrier_field) || "";
        my $historical_doi = _extract_doi_like($value);
        next if $historical_doi eq "";

        my $doi_id = $self->_managed_doi_eprintid($historical_doi);

        if( defined $doi_id )
        {
            if( $doi_id != $id )
            {
                return (
                    "BLOCK_WRONG_MANAGED_IDENTIFIER",
                    $historical_doi,
                    "historical identifier field '$barrier_field' contains managed eprintid $doi_id but record is $id"
                );
            }

            return (
                "CHECK_LOCAL_MANAGED_IDENTIFIER",
                $historical_doi,
                "managed DOI exists only in historical identifier field '$barrier_field'; authenticated remote review required"
            );
        }

        return (
            "BLOCK_EXISTING_EXTERNAL_DOI",
            $historical_doi,
            "historical identifier field '$barrier_field' already contains a DOI-like identifier; a second DOI must not be minted"
        );
    }

    return (
        "BLOCK",
        "",
        "eprint type is not enabled for new DataCite DOI creation"
    ) unless $self->_mint_type_allowed($dataobj);

    my( $metadata_ok, $metadata_reason ) =
        $self->_metadata_preflight($dataobj);

    return ("BLOCK_METADATA", "", $metadata_reason)
        unless $metadata_ok;

    my $candidate = $self->_canonical_doi_candidate($dataobj);

    return (
        "BLOCK",
        "",
        "canonical DataCite DOI candidate could not be calculated"
    ) if $candidate eq "";

    return (
        "MINT",
        $candidate,
        "no DOI-like duplicate barrier is present and mandatory local metadata are available"
    );
}


############################################################
# Resolve DataCite credentials.
#
# Explicit credentials have precedence.
# Otherwise use the protected API-key file.
############################################################

sub _datacite_credentials
{
    my( $self, $username, $password ) = @_;

    if(
        defined $username
        && $username ne ""
    )
    {
        $password = ""
            unless defined $password;

        return (
            $username,
            $password,
            undef
        );
    }

    my $repository =
        $self->repository();

    return (
        undef,
        undef,
        "missing repository"
    ) unless defined $repository;

    my $file =
        $repository->get_conf(
            "datacitedoi",
            "credential_file"
        );

    unless(
        defined $file
        && $file ne ""
    )
    {
        return (
            undef,
            undef,
            "DataCite credential file is not configured"
        );
    }

    unless( -f $file )
    {
        return (
            undef,
            undef,
            "DataCite credential file does not exist"
        );
    }

    my $fh;

    unless( open( $fh, "<", $file ) )
    {
        return (
            undef,
            undef,
            "DataCite credential file cannot be opened: $!"
        );
    }

    my $key = <$fh>;

    close( $fh );

    unless( defined $key )
    {
        return (
            undef,
            undef,
            "DataCite credential file is empty"
        );
    }

    $key =~ s/[\r\n]+$//;

    unless( $key ne "" )
    {
        return (
            undef,
            undef,
            "DataCite API key is empty"
        );
    }

    return (
        $key,
        "",
        undef
    );
}


############################################################
# Authenticated Member API GET.
#
# READ ONLY.
# Exactly one GET.
# No retry.
############################################################


############################################################
# Publish a repository DOI previously created as a DataCite Draft.
#
# Safety model:
#
#   1. hard EPrints current_user allowlist is FIRST;
#   2. exact PUBLISH_FINDABLE confirmation;
#   3. credentials resolved only after both local gates;
#   4. local classifier must still say MINT;
#   5. dedicated local doi field must still be empty;
#   6. fresh authenticated GET of the candidate DOI;
#   7. exact DOI/client/landing-URL verification;
#   8. PUT is allowed only from state=draft;
#   9. exactly ONE PUT; NO retry;
#  10. fresh authenticated GET after PUT;
#  11. local DOI persistence ONLY after remote Findable
#      has been independently verified;
#  12. if the DOI is already Findable, NO PUT is sent:
#      only safe local reconciliation may occur.
############################################################

sub publish_mint_findable
{
    my(
        $self,
        $dataobj,
        $username,
        $password,
        $confirmation
    ) = @_;

    #
    # HARD GATE 1.
    #
    # This MUST remain the first operation in every
    # DataCite write method.
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $self->_write_authorised();

    unless( $write_ok )
    {
        return (
            "BLOCK_UNAUTHORISED_USER",
            "",
            $write_reason,
            undef
        );
    }

    #
    # HARD GATE 2.
    #
    unless(
        defined $confirmation
        && $confirmation eq "PUBLISH_FINDABLE"
    )
    {
        return (
            "BLOCK_CONFIRMATION_REQUIRED",
            "",
            "explicit PUBLISH_FINDABLE confirmation is required",
            undef
        );
    }

    unless( defined $dataobj )
    {
        return (
            "BLOCK_NO_EPRINT",
            "",
            "missing EPrint object",
            undef
        );
    }

    #
    # Resolve credentials only AFTER both hard gates.
    #
    my(
        $resolved_username,
        $resolved_password,
        $credential_error
    ) =
        $self->_datacite_credentials(
            $username,
            $password
        );

    unless( defined $resolved_username )
    {
        return (
            "BLOCK_CREDENTIALS",
            "",
            $credential_error
                || "DataCite authentication credentials unavailable",
            undef
        );
    }

    $username = $resolved_username;
    $password = $resolved_password;

    my $repository =
        $self->repository();

    unless( defined $repository )
    {
        return (
            "BLOCK_REPOSITORY",
            "",
            "missing EPrints repository",
            undef
        );
    }

    #
    # The item must still be locally eligible to mint.
    #
    # For a newly-created remote Draft the local doi field is
    # intentionally still empty, so classify_datacite() should
    # still return MINT and the canonical candidate DOI.
    #
    my(
        $local_mode,
        $doi,
        $local_reason
    ) =
        $self->classify_datacite(
            $dataobj
        );

    unless( $local_mode eq "MINT" )
    {
        return (
            "BLOCK_LOCAL_STATE",
            $doi,
            "Findable publication requires local mode MINT; "
                . "found '$local_mode': $local_reason",
            undef
        );
    }

    $doi =
        _normalise_doi(
            $doi || ""
        );

    if( $doi eq "" )
    {
        return (
            "BLOCK_LOCAL_STATE",
            "",
            "canonical DOI candidate is empty",
            undef
        );
    }

    #
    # The dedicated local DOI MUST still be empty.
    #
    my $doi_field = $self->_doi_field();

    my $local_doi =
        _normalise_doi(
            $dataobj->get_value( $doi_field )
                || ""
        );

    if( $local_doi ne "" )
    {
        return (
            "BLOCK_LOCAL_DOI_ALREADY_SET",
            $doi,
            "dedicated local doi field is already populated",
            undef
        );
    }

    #
    # Canonical public landing URL.
    #
    my $landing_url =
        $dataobj->url();

    unless(
        defined $landing_url
        && $landing_url =~ m{^https?://}i
    )
    {
        return (
            "BLOCK_LANDING_URL",
            $doi,
            "EPrint public landing URL is missing or invalid",
            undef
        );
    }

    #
    # Fresh authenticated GET of the remote candidate.
    #
    my(
        $http_code,
        $remote,
        $http_reason
    ) =
        $self->_datacite_member_get(
            $doi,
            $username,
            $password
        );

    unless(
        defined $http_code
        && $http_code == 200
        && defined $remote
    )
    {
        return (
            "BLOCK_REMOTE_DRAFT",
            $doi,
            "candidate DOI cannot be retrieved through the "
                . "authenticated DataCite API"
                . (
                    defined $http_code
                    ? " (HTTP $http_code)"
                    : ""
                  )
                . ": "
                . (
                    $http_reason
                    || "unknown error"
                  ),
            undef
        );
    }

    #
    # Exact DOI + DataCite client ownership.
    #
    my(
        $identity_ok,
        $identity_reason
    ) =
        $self->_verify_remote_identity(
            $doi,
            $remote
        );

    unless( $identity_ok )
    {
        return (
            "BLOCK_OWNERSHIP",
            $doi,
            $identity_reason,
            $remote
        );
    }

    #
    # Exact landing URL.
    #
    my $remote_url =
        $remote->{url}
        || "";

    unless(
        $remote_url ne ""
        && $remote_url eq $landing_url
    )
    {
        return (
            "BLOCK_REMOTE_URL",
            $doi,
            "remote DataCite landing URL differs from "
                . "the current EPrint landing URL",
            $remote
        );
    }

    my $state =
        lc(
            $remote->{state}
            || ""
        );

    my $put_performed = 0;

    #
    # If a previous Publish request succeeded remotely but its
    # response was lost, NEVER publish again.
    #
    # A verified Findable DOI goes directly to local
    # reconciliation.
    #
    if( $state eq "findable" )
    {
        $put_performed = 0;
    }
    elsif( $state eq "draft" )
    {
        #
        # DataCite supports partial PUT updates.
        # For a complete Draft, event=publish is sufficient.
        #
        require JSON::PP;
        require HTTP::Request;

        my $json =
            JSON::PP->new
                ->utf8
                ->canonical
                ->encode(
                    {
                        data => {
                            type => "dois",
                            attributes => {
                                event => "publish",
                            },
                        },
                    }
                );

        my $base =
            $repository->get_conf(
                "datacitedoi",
                "rest_apiurl"
            ) || "https://api.datacite.org";

        $base =~ s{/$}{};

        my $put_url =
            $base
            . "/dois/"
            . $doi;

        my $auth =
            "Basic "
            . encode_base64(
                $username . ":" . $password,
                ""
            );

        my $request =
            HTTP::Request->new(
                "PUT",
                $put_url
            );

        $request->header(
            "Content-Type" =>
                "application/vnd.api+json"
        );

        $request->header(
            "Accept" =>
                "application/vnd.api+json"
        );

        $request->header(
            "Authorization" =>
                $auth
        );

        $request->content(
            $json
        );

        my $ua =
            LWP::UserAgent->new(
                timeout => 30,
                agent   =>
                    "EPrints-DataCite-REST-publish/1.0",
            );

        #
        # EXACTLY ONE PUT.
        # NO retry.
        #
        my $response =
            $ua->request(
                $request
            );

        $put_performed = 1;

        #
        # Regardless of the HTTP result, do a fresh authenticated
        # GET before deciding what happened.
        #
        my(
            $after_code,
            $after_remote,
            $after_reason
        ) =
            $self->_datacite_member_get(
                $doi,
                $username,
                $password
            );

        unless(
            defined $after_code
            && $after_code == 200
            && defined $after_remote
        )
        {
            return (
                "PUBLISH_SENT_REMOTE_UNVERIFIED",
                $doi,
                "one DataCite PUT was sent"
                    . "; PUT HTTP="
                    . $response->code
                    . " "
                    . $response->message
                    . "; subsequent authenticated GET failed"
                    . (
                        defined $after_code
                        ? " (HTTP $after_code)"
                        : ""
                      )
                    . ": "
                    . (
                        $after_reason
                        || "unknown error"
                      )
                    . "; DO NOT retry publication automatically",
                undef
            );
        }

        my(
            $after_identity_ok,
            $after_identity_reason
        ) =
            $self->_verify_remote_identity(
                $doi,
                $after_remote
            );

        unless( $after_identity_ok )
        {
            return (
                "PUBLISH_SENT_IDENTITY_UNVERIFIED",
                $doi,
                "one DataCite PUT was sent, but post-write "
                    . "identity verification failed: "
                    . $after_identity_reason
                    . "; DO NOT retry publication automatically",
                $after_remote
            );
        }

        my $after_url =
            $after_remote->{url}
            || "";

        unless(
            $after_url ne ""
            && $after_url eq $landing_url
        )
        {
            return (
                "PUBLISH_SENT_URL_MISMATCH",
                $doi,
                "one DataCite PUT was sent and the DOI is "
                    . "retrievable, but the landing URL differs "
                    . "from the EPrint landing URL; "
                    . "DO NOT retry publication automatically",
                $after_remote
            );
        }

        my $after_state =
            lc(
                $after_remote->{state}
                || ""
            );

        unless( $after_state eq "findable" )
        {
            return (
                "PUBLISH_NOT_CONFIRMED",
                $doi,
                "one DataCite PUT was sent"
                    . "; PUT HTTP="
                    . $response->code
                    . " "
                    . $response->message
                    . "; subsequent authenticated GET reports "
                    . "state='"
                    . (
                        $after_remote->{state}
                        || "[unknown]"
                      )
                    . "'; local DOI was NOT stored",
                $after_remote
            );
        }

        #
        # Findable is now independently confirmed.
        #
        $remote = $after_remote;
        $state  = "findable";
    }
    else
    {
        return (
            "BLOCK_REMOTE_STATE",
            $doi,
            "candidate DOI exists in unexpected remote state "
                . "'"
                . (
                    $remote->{state}
                    || "[unknown]"
                  )
                . "'; expected Draft or Findable",
            $remote
        );
    }

    #
    # From here onward the remote DOI has been independently
    # verified as Findable and owned by the expected client.
    #
    # Re-check local field immediately before persistence.
    #
    my $current_local =
        _normalise_doi(
            $dataobj->get_value( $doi_field )
                || ""
        );

    if( $current_local ne "" )
    {
        if(
            lc( $current_local )
            eq lc( $doi )
        )
        {
            return (
                "FINDABLE_ALREADY_LOCAL",
                $doi,
                "remote DOI is Findable and the same DOI is "
                    . "already present locally; no local write needed",
                $remote
            );
        }

        return (
            "FINDABLE_LOCAL_CONFLICT",
            $doi,
            "remote DOI is Findable but the local doi field "
                . "became populated with a different value; "
                . "manual reconciliation required",
            $remote
        );
    }

    #
    # LOCAL PERSISTENCE.
    #
    # This occurs ONLY after Findable has been verified remotely.
    #
    my $commit_ok =
        eval
        {
            $dataobj->set_value(
                $doi_field,
                $doi
            );

            $dataobj->commit();

            1;
        };

    unless( $commit_ok )
    {
        my $error =
            $@ || "unknown EPrints commit error";

        $error =~ s/\s+$//;

        $repository->log(
            "[DataCiteEventREST WRITE] "
            . "action=findable_remote_only "
            . "eprint=" . $dataobj->id . " "
            . "userid=$acting_userid "
            . "doi=[$doi] "
            . "state=findable "
            . "local_commit=FAILED"
        );

        return (
            "FINDABLE_LOCAL_PERSIST_FAILED",
            $doi,
            "DataCite DOI is confirmed Findable, but local "
                . "EPrints DOI persistence failed: $error; "
                . "DO NOT publish again; reconcile locally",
            $remote
        );
    }

    my $action =
        $put_performed
        ? "publish_findable"
        : "reconcile_findable";

    $repository->log(
        "[DataCiteEventREST WRITE] "
        . "action=$action "
        . "eprint=" . $dataobj->id . " "
        . "userid=$acting_userid "
        . "doi=[$doi] "
        . "state=findable "
        . "local_commit=OK"
    );

    if( $put_performed )
    {
        return (
            "FINDABLE_PUBLISHED",
            $doi,
            "DataCite DOI was published to Findable by "
                . "authorised EPrints userid $acting_userid "
                . "and stored locally only after remote "
                . "Findable verification",
            $remote
        );
    }

    return (
        "FINDABLE_RECONCILED",
        $doi,
        "DataCite DOI was already Findable; no PUT was sent; "
            . "the verified DOI was safely reconciled into "
            . "the local EPrints doi field",
        $remote
    );
}


sub _datacite_member_get
{
    my( $self, $doi, $username, $password ) = @_;

    my $repository =
        $self->repository();

    return (
        undef,
        undef,
        "missing repository"
    ) unless defined $repository;

    my(
        $resolved_username,
        $resolved_password,
        $credential_error
    ) =
        $self->_datacite_credentials(
            $username,
            $password
        );

    unless( defined $resolved_username )
    {
        return (
            undef,
            undef,
            $credential_error
                || "missing DataCite authentication credentials"
        );
    }

    $username = $resolved_username;
    $password = $resolved_password;

    my $base =
        $repository->get_conf(
            "datacitedoi",
            "rest_apiurl"
        ) || "https://api.datacite.org";

    $base =~ s{/$}{};

    #
    # Only verified managed repository DOI are passed to this function.
    #
    my $url =
        $base
        . "/dois/"
        . $doi
        . "?publisher=true&affiliation=true&detail=true";

    my $ua =
        LWP::UserAgent->new(
            timeout => 20,
            agent   => "EPrints-DataCite-REST-member-preflight/1.0",
        );

    my $auth =
        "Basic "
        . encode_base64(
            $username . ":" . $password,
            ""
        );

    my $response =
        $ua->get(
            $url,
            "Accept" =>
                "application/vnd.api+json",
            "Authorization" =>
                $auth
        );

    if( $response->code == 404 )
    {
        return (
            404,
            undef,
            "Not Found"
        );
    }

    unless( $response->is_success )
    {
        return (
            $response->code,
            undef,
            $response->status_line
        );
    }

    my $json;

    my $ok = eval
    {
        $json =
            decode_json(
                $response->content
            );

        1;
    };

    unless( $ok )
    {
        my $error =
            $@ || "unknown JSON error";

        $error =~ s/\s+$//;

        return (
            $response->code,
            undef,
            "invalid DataCite JSON response: $error"
        );
    }

    unless(
        ref( $json ) eq "HASH"
        && ref( $json->{data} ) eq "HASH"
        && ref( $json->{data}->{attributes} ) eq "HASH"
    )
    {
        return (
            $response->code,
            undef,
            "unexpected DataCite JSON structure"
        );
    }

    #
    # The DataCite repository/client responsible for the DOI is
    # represented as a JSON:API relationship, not as DOI metadata.
    #
    # Preserve it alongside the returned attributes under a private
    # integration-only key so subsequent ownership checks do not lose
    # this information.
    #
    my $attributes =
        $json->{data}->{attributes};

    my $relationships =
        $json->{data}->{relationships};

    if(
        ref( $relationships ) eq "HASH"
        && ref( $relationships->{client} ) eq "HASH"
        && ref( $relationships->{client}->{data} ) eq "HASH"
    )
    {
        my $client_id =
            $relationships->{client}->{data}->{id}
            || "";

        if( $client_id ne "" )
        {
            $attributes->{_datacite_client_id} =
                $client_id;
        }
    }

    return (
        $response->code,
        $attributes,
        "OK"
    );
}


############################################################
# Effective DataCite schema.
#
# Fall back to stored XML when schemaVersion is missing.
############################################################

sub _datacite_effective_schema
{
    my( $self, $attributes ) = @_;

    return ""
        unless defined $attributes
        && ref( $attributes ) eq "HASH";

    my $schema =
        $attributes->{schemaVersion}
        || "";

    return $schema
        if $schema ne "";

    my $encoded =
        $attributes->{xml};

    return ""
        unless defined $encoded
        && $encoded ne "";

    my $xml =
        decode_base64(
            $encoded
        );

    if(
        defined $xml
        && $xml =~
           m{<resource\b[^>]*\bxmlns\s*=\s*["']([^"']+)["']}is
    )
    {
        return $1;
    }

    return "";
}


############################################################
# Verify remote DOI and DataCite client ownership.
############################################################

sub _verify_remote_identity
{
    my( $self, $doi, $attributes ) = @_;

    return (
        0,
        "missing remote attributes"
    ) unless
        defined $attributes
        && ref( $attributes ) eq "HASH";

    my $remote_doi =
        _normalise_doi(
            $attributes->{doi}
            || ""
        );

    unless(
        $remote_doi ne ""
        && lc( $remote_doi ) eq lc( $doi )
    )
    {
        return (
            0,
            "DataCite returned DOI [$remote_doi] but [$doi] was requested"
        );
    }

    my $repository =
        $self->repository();

    my $expected_client =
        $repository->get_conf(
            "datacitedoi",
            "client_id"
        ) || "";

    return (
        0,
        "expected DataCite client_id is not configured"
    ) if $expected_client eq "";

    my $remote_client =
        $attributes->{_datacite_client_id}
        || "";

    unless(
        $remote_client ne ""
        && lc( $remote_client ) eq lc( $expected_client )
    )
    {
        return (
            0,
            "DataCite client ownership mismatch: expected [$expected_client], found [$remote_client]"
        );
    }

    return (
        1,
        "remote DOI and DataCite client ownership match"
    );
}


############################################################
# Authenticated DataCite preflight.
#
# GET ONLY.
#
# Possible final modes include:
#
#   MINT_READY
#   UPDATE_MODERN
#   MIGRATE_LEGACY
#
#   BLOCK_BROKEN_LOCAL_DOI
#   BLOCK_MANAGED_DOI_NOT_MIGRATED
#   BLOCK_CANDIDATE_EXISTS
#   BLOCK_OWNERSHIP
#   BLOCK_REMOTE_STATE
#
# plus local BLOCK_* modes.
############################################################

sub preflight_datacite_authenticated
{
    my( $self, $dataobj, $username, $password ) = @_;

    my(
        $local_mode,
        $doi,
        $local_reason
    ) =
        $self->classify_datacite(
            $dataobj
        );

    if(
        $local_mode =~ /^BLOCK/
    )
    {
        return (
            $local_mode,
            $doi,
            $local_reason,
            undef
        );
    }

    unless(
           $local_mode eq "MINT"
        || $local_mode eq "UPDATE"
        || $local_mode eq "CHECK_LOCAL_MANAGED_IDENTIFIER"
    )
    {
        return (
            "BLOCK",
            $doi,
            "unexpected local DataCite mode '$local_mode'",
            undef
        );
    }

    my(
        $http_code,
        $attributes,
        $http_reason
    ) =
        $self->_datacite_member_get(
            $doi,
            $username,
            $password
        );

    #
    # --------------------------------------------------------
    # New DOI candidate.
    # --------------------------------------------------------
    #
    if( $local_mode eq "MINT" )
    {
        if(
            defined $http_code
            && $http_code == 404
        )
        {
            return (
                "MINT_READY",
                $doi,
                "authenticated DataCite preflight found no existing record for the candidate DOI",
                undef
            );
        }

        if(
            defined $http_code
            && $http_code == 200
            && defined $attributes
        )
        {
            my $state =
                $attributes->{state}
                || "[unknown]";

            my $client =
                $attributes->{_datacite_client_id}
                || "[unknown]";

            return (
                "BLOCK_CANDIDATE_EXISTS",
                $doi,
                "candidate DOI already exists in DataCite (state='$state', clientId='$client')",
                $attributes
            );
        }

        return (
            "BLOCK",
            $doi,
            "authenticated DataCite candidate check failed"
                . (
                    defined $http_code
                    ? " (HTTP $http_code)"
                    : ""
                  )
                . ": "
                . (
                    $http_reason
                    || "unknown error"
                  ),
            undef
        );
    }

    #
    # --------------------------------------------------------
    # Historical canonical-looking DOI only in id_number.
    # --------------------------------------------------------
    #
    if(
        $local_mode eq
        "CHECK_LOCAL_MANAGED_IDENTIFIER"
    )
    {
        if(
            defined $http_code
            && $http_code == 404
        )
        {
            return (
                "BLOCK_BROKEN_LOCAL_DOI",
                $doi,
                "historical identifier field contains the canonical-looking managed DOI but DataCite Member API returns 404; manual review required",
                undef
            );
        }

        unless(
            defined $http_code
            && $http_code == 200
            && defined $attributes
        )
        {
            return (
                "BLOCK",
                $doi,
                "historical managed DOI could not be reviewed through the authenticated DataCite API"
                    . (
                        defined $http_code
                        ? " (HTTP $http_code)"
                        : ""
                      )
                    . ": "
                    . (
                        $http_reason
                        || "unknown error"
                      ),
                undef
            );
        }

        my(
            $identity_ok,
            $identity_reason
        ) =
            $self->_verify_remote_identity(
                $doi,
                $attributes
            );

        unless( $identity_ok )
        {
            return (
                "BLOCK_OWNERSHIP",
                $doi,
                $identity_reason,
                $attributes
            );
        }

        my $state =
            $attributes->{state}
            || "[unknown]";

        return (
            "BLOCK_MANAGED_DOI_NOT_MIGRATED",
            $doi,
            "DataCite confirms that this DOI belongs to the configured DataCite client (state='$state'), but it exists only in historical id_number; explicit migration to the dedicated doi field is required",
            $attributes
        );
    }

    #
    # --------------------------------------------------------
    # Existing DOI in dedicated doi field.
    # --------------------------------------------------------
    #
    unless(
        defined $http_code
        && $http_code == 200
        && defined $attributes
    )
    {
        return (
            "BLOCK",
            $doi,
            "managed repository DOI could not be retrieved through the authenticated DataCite API"
                . (
                    defined $http_code
                    ? " (HTTP $http_code)"
                    : ""
                  )
                . ": "
                . (
                    $http_reason
                    || "unknown error"
                  ),
            undef
        );
    }

    my(
        $identity_ok,
        $identity_reason
    ) =
        $self->_verify_remote_identity(
            $doi,
            $attributes
        );

    unless( $identity_ok )
    {
        return (
            "BLOCK_OWNERSHIP",
            $doi,
            $identity_reason,
            $attributes
        );
    }

    my $state =
        $attributes->{state}
        || "";

    unless(
        lc( $state ) eq "findable"
    )
    {
        return (
            "BLOCK_REMOTE_STATE",
            $doi,
            "managed repository DOI exists but is not Findable (state='$state'); explicit review required",
            $attributes
        );
    }

    my $schema =
        $self->_datacite_effective_schema(
            $attributes
        );

    if(
        $schema eq
        "http://datacite.org/schema/kernel-4"
    )
    {
        return (
            "UPDATE_MODERN",
            $doi,
            "managed repository DOI is Findable, belongs to the configured DataCite client and uses DataCite kernel-4",
            $attributes
        );
    }

    if(
        $schema =~
        m{^https?://datacite\.org/schema/kernel-[0-9]}i
    )
    {
        return (
            "MIGRATE_LEGACY",
            $doi,
            "managed repository DOI is Findable and uses legacy schema '$schema'",
            $attributes
        );
    }

    return (
        "BLOCK",
        $doi,
        "unable to determine a recognised DataCite metadata schema",
        $attributes
    );
}


############################################################
# Prepare DataCite XML locally.
#
# NO NETWORK ACCESS.
############################################################


############################################################
# Canonicalise one DataCite top-level XML property.
############################################################

sub _datacite_canonical_property
{
    my( $node ) = @_;

    require XML::LibXML;

    my $clone =
        $node->cloneNode(1);

    for my $text (
        $clone->findnodes('.//text()')
    )
    {
        my $value =
            $text->data;

        $value =~ s/\s+/ /g;
        $value =~ s/^\s+//;
        $value =~ s/\s+$//;

        if( $value eq "" )
        {
            $text->unbindNode();
        }
        else
        {
            $text->setData(
                $value
            );
        }
    }

    return $clone->toStringC14N(0);
}


############################################################
# Compare DataCite XML semantically by top-level property.
#
# Root serialisation, indentation and schemaLocation are not
# treated as metadata differences.
#
# Returns:
#
#   ($same, \@different_property_names, $reason)
############################################################

sub _compare_datacite_xml
{
    my(
        $self,
        $remote_xml,
        $local_xml
    ) = @_;

    unless(
        defined $remote_xml
        && $remote_xml ne ""
        && defined $local_xml
        && $local_xml ne ""
    )
    {
        return (
            0,
            [],
            "remote or local DataCite XML is empty"
        );
    }

    require XML::LibXML;

    my $parser =
        XML::LibXML->new();

    $parser->keep_blanks(0);

    my(
        $remote_doc,
        $local_doc
    );

    my $parse_ok =
        eval
        {
            $remote_doc =
                $parser->load_xml(
                    string => $remote_xml
                );

            $local_doc =
                $parser->load_xml(
                    string => $local_xml
                );

            1;
        };

    unless( $parse_ok )
    {
        my $error =
            $@ || "unknown XML parsing error";

        $error =~ s/\s+$//;

        return (
            0,
            [],
            "DataCite XML parsing failed: $error"
        );
    }

    my %remote;
    my %local;

    for my $pair (
        [ $remote_doc, \%remote ],
        [ $local_doc,  \%local  ]
    )
    {
        my(
            $doc,
            $target
        ) = @{$pair};

        my $root =
            $doc->documentElement();

        for my $node (
            $root->childNodes()
        )
        {
            next
                unless $node->nodeType
                    == 1;    # DOM ELEMENT_NODE

            my $name =
                $node->localname();

            push(
                @{ $target->{$name} },
                _datacite_canonical_property(
                    $node
                )
            );
        }
    }

    my %all =
        map { $_ => 1 }
        (
            keys %remote,
            keys %local
        );

    my @different;

    for my $name (
        sort keys %all
    )
    {
        my $remote_value =
            join(
                "\n",
                @{ $remote{$name} || [] }
            );

        my $local_value =
            join(
                "\n",
                @{ $local{$name} || [] }
            );

        if(
            $remote_value ne
            $local_value
        )
        {
            push(
                @different,
                $name
            );
        }
    }

    if( @different )
    {
        return (
            0,
            \@different,
            "DataCite metadata differ in properties: "
                . join(
                    ", ",
                    @different
                  )
        );
    }

    return (
        1,
        [],
        "remote and local DataCite metadata are semantically identical"
    );
}


############################################################
# READ-ONLY preparation for UPDATE_MODERN.
#
# This function performs authenticated GET operations only.
# It NEVER performs PUT/POST/DELETE and NEVER modifies EPrints.
#
# Current conservative policy:
#
#   - DOI must classify as UPDATE_MODERN;
#   - remote/local DataCite XML must be semantically identical;
#   - if URLs are equal => UPDATE_NOOP;
#   - otherwise only an exact http -> https scheme upgrade of
#     the same host/path/query/fragment is eligible.
############################################################


############################################################
# Update ONLY the landing URL of an existing modern
# DataCite DOI from HTTP to the exact corresponding HTTPS URL.
#
# No XML or metadata property is submitted.
#
# Safety:
#   1. current-user hard gate FIRST;
#   2. exact UPDATE_URL_HTTPS confirmation;
#   3. credentials only after both gates;
#   4. fresh prepare_update_modern();
#   5. only UPDATE_URL_HTTPS_READY is accepted;
#   6. payload contains ONLY "url";
#   7. exactly ONE PUT, NO retry;
#   8. fresh authenticated GET after PUT;
#   9. DOI/client/state/URL reverified;
#  10. fresh semantic compare must end in UPDATE_NOOP.
############################################################

sub update_modern_url_https
{
    my(
        $self,
        $dataobj,
        $username,
        $password,
        $confirmation
    ) = @_;

    #
    # HARD GATE 1 -- MUST remain first.
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $self->_write_authorised();

    unless( $write_ok )
    {
        return (
            "BLOCK_UNAUTHORISED_USER",
            "",
            $write_reason,
            undef
        );
    }

    #
    # HARD GATE 2.
    #
    unless(
        defined $confirmation
        && $confirmation eq "UPDATE_URL_HTTPS"
    )
    {
        return (
            "BLOCK_CONFIRMATION_REQUIRED",
            "",
            "explicit UPDATE_URL_HTTPS confirmation is required",
            undef
        );
    }

    unless( defined $dataobj )
    {
        return (
            "BLOCK_NO_EPRINT",
            "",
            "missing EPrint object",
            undef
        );
    }

    #
    # Resolve credentials only after both local gates.
    #
    my(
        $resolved_username,
        $resolved_password,
        $credential_error
    ) =
        $self->_datacite_credentials(
            $username,
            $password
        );

    unless( defined $resolved_username )
    {
        return (
            "BLOCK_CREDENTIALS",
            "",
            $credential_error
                || "DataCite authentication credentials unavailable",
            undef
        );
    }

    $username = $resolved_username;
    $password = $resolved_password;

    #
    # Fresh authenticated GET + ownership + state +
    # semantic metadata comparison + URL comparison.
    #
    my(
        $prepare_mode,
        $doi,
        $prepare_reason,
        $remote
    ) =
        $self->prepare_update_modern(
            $dataobj,
            $username,
            $password
        );

    unless(
        $prepare_mode eq "UPDATE_URL_HTTPS_READY"
        && defined $remote
    )
    {
        return (
            "BLOCK_UPDATE_NOT_READY",
            $doi,
            $prepare_reason,
            $remote
        );
    }

    my $repository =
        $self->repository();

    unless( defined $repository )
    {
        return (
            "BLOCK_REPOSITORY",
            $doi,
            "missing EPrints repository",
            $remote
        );
    }

    my $remote_url =
        $remote->{url}
        || "";

    my $local_url =
        $remote->{_datacite_local_url}
        || $dataobj->url()
        || "";

    #
    # Repeat the narrow URL invariant immediately before PUT.
    #
    my $remote_rest =
        $remote_url;

    my $local_rest =
        $local_url;

    unless(
        $remote_rest =~ s{^http://}{}i
        && $local_rest =~ s{^https://}{}i
        && $remote_rest eq $local_rest
    )
    {
        return (
            "BLOCK_URL_INVARIANT",
            $doi,
            "URL invariant changed before PUT; expected exact HTTP-to-HTTPS upgrade",
            $remote
        );
    }

    #
    # Build the deliberately minimal partial-update payload.
    #
    # NO doi, xml, event or metadata properties are submitted.
    #
    my $json =
        encode_json(
            {
                data => {
                    type => "dois",
                    attributes => {
                        url => $local_url,
                    },
                },
            }
        );

    my $decoded;

    my $decode_ok =
        eval
        {
            $decoded =
                decode_json(
                    $json
                );

            1;
        };

    unless(
        $decode_ok
        && ref($decoded) eq "HASH"
        && ref($decoded->{data}) eq "HASH"
        && ref($decoded->{data}->{attributes}) eq "HASH"
    )
    {
        return (
            "BLOCK_PAYLOAD",
            $doi,
            "URL update payload could not be decoded safely",
            $remote
        );
    }

    my $attributes =
        $decoded->{data}->{attributes};

    my @keys =
        sort keys %{$attributes};

    unless(
        @keys == 1
        && $keys[0] eq "url"
        && defined $attributes->{url}
        && $attributes->{url} eq $local_url
    )
    {
        return (
            "BLOCK_PAYLOAD",
            $doi,
            "URL update payload contains attributes other than the single verified url",
            $remote
        );
    }

    #
    # Construct authenticated PUT request.
    #
    require HTTP::Request;

    my $base =
        $repository->get_conf(
            "datacitedoi",
            "rest_apiurl"
        ) || "https://api.datacite.org";

    $base =~ s{/$}{};

    my $put_url =
        $base
        . "/dois/"
        . $doi;

    my $auth =
        "Basic "
        . encode_base64(
            $username . ":" . $password,
            ""
        );

    my $request =
        HTTP::Request->new(
            "PUT",
            $put_url
        );

    $request->header(
        "Content-Type" =>
            "application/vnd.api+json"
    );

    $request->header(
        "Accept" =>
            "application/vnd.api+json"
    );

    $request->header(
        "Authorization" =>
            $auth
    );

    $request->content(
        $json
    );

    my $ua =
        LWP::UserAgent->new(
            timeout => 30,
            agent   =>
                "EPrints-DataCite-REST-url-update/1.0",
        );

    #
    # EXACTLY ONE PUT.
    # NO automatic retry.
    #
    my $response =
        $ua->request(
            $request
        );

    #
    # Regardless of HTTP result, establish final truth through
    # a fresh authenticated GET.
    #
    my(
        $after_code,
        $after_remote,
        $after_reason
    ) =
        $self->_datacite_member_get(
            $doi,
            $username,
            $password
        );

    unless(
        defined $after_code
        && $after_code == 200
        && defined $after_remote
    )
    {
        return (
            "UPDATE_SENT_REMOTE_UNVERIFIED",
            $doi,
            "one DataCite URL PUT was sent"
                . "; PUT HTTP="
                . $response->code
                . " "
                . $response->message
                . "; subsequent authenticated GET failed"
                . (
                    defined $after_code
                    ? " (HTTP $after_code)"
                    : ""
                  )
                . ": "
                . (
                    $after_reason
                    || "unknown error"
                  )
                . "; DO NOT retry automatically",
            undef
        );
    }

    my(
        $identity_ok,
        $identity_reason
    ) =
        $self->_verify_remote_identity(
            $doi,
            $after_remote
        );

    unless( $identity_ok )
    {
        return (
            "UPDATE_SENT_IDENTITY_UNVERIFIED",
            $doi,
            "one DataCite URL PUT was sent, but post-write "
                . "identity verification failed: "
                . $identity_reason
                . "; DO NOT retry automatically",
            $after_remote
        );
    }

    my $after_state =
        lc(
            $after_remote->{state}
            || ""
        );

    unless( $after_state eq "findable" )
    {
        return (
            "UPDATE_SENT_STATE_MISMATCH",
            $doi,
            "one DataCite URL PUT was sent, but the DOI is no longer Findable; "
                . "DO NOT retry automatically",
            $after_remote
        );
    }

    my $after_url =
        $after_remote->{url}
        || "";

    unless(
        $after_url ne ""
        && $after_url eq $local_url
    )
    {
        return (
            "UPDATE_NOT_CONFIRMED",
            $doi,
            "one DataCite URL PUT was sent"
                . "; PUT HTTP="
                . $response->code
                . " "
                . $response->message
                . "; subsequent authenticated GET reports url=["
                . $after_url
                . "]; expected=["
                . $local_url
                . "]; DO NOT retry automatically",
            $after_remote
        );
    }

    #
    # One more complete semantic comparison:
    # after the URL change there must be NOTHING left to update.
    #
    my(
        $final_mode,
        $final_doi,
        $final_reason,
        $final_remote
    ) =
        $self->prepare_update_modern(
            $dataobj,
            $username,
            $password
        );

    unless(
        $final_mode eq "UPDATE_NOOP"
        && defined $final_doi
        && lc(_normalise_doi($final_doi))
            eq lc(_normalise_doi($doi))
    )
    {
        return (
            "UPDATE_URL_APPLIED_FINAL_COMPARE_FAILED",
            $doi,
            "DataCite URL now matches the repository, but final semantic comparison did not return UPDATE_NOOP: "
                . $final_reason,
            (
                defined $final_remote
                ? $final_remote
                : $after_remote
            )
        );
    }

    $repository->log(
        "[DataCiteEventREST WRITE] "
        . "action=update_url_https "
        . "eprint=" . $dataobj->id . " "
        . "userid=$acting_userid "
        . "doi=[$doi] "
        . "old_url=[$remote_url] "
        . "new_url=[$local_url]"
    );

    return (
        "UPDATE_URL_HTTPS_DONE",
        $doi,
        "DataCite landing URL updated from HTTP to HTTPS by authorised EPrints userid $acting_userid; metadata were not submitted and final comparison is UPDATE_NOOP",
        $final_remote
    );
}


sub prepare_update_modern
{
    my(
        $self,
        $dataobj,
        $username,
        $password
    ) = @_;

    unless( defined $dataobj )
    {
        return (
            "BLOCK_NO_EPRINT",
            "",
            "missing EPrint object",
            undef
        );
    }

    #
    # Fresh authenticated DataCite preflight.
    #
    my(
        $preflight_mode,
        $doi,
        $preflight_reason,
        $remote
    ) =
        $self->preflight_datacite_authenticated(
            $dataobj,
            $username,
            $password
        );

    unless(
        $preflight_mode eq "UPDATE_MODERN"
        && defined $remote
    )
    {
        return (
            $preflight_mode,
            $doi,
            $preflight_reason,
            $remote
        );
    }

    #
    # Generate current authoritative repository XML.
    #
    my(
        $prepare_mode,
        $local_doi,
        $prepare_reason,
        $local_xml
    ) =
        $self->prepare_datacite(
            $dataobj
        );

    unless(
        $prepare_mode eq "UPDATE"
        && defined $local_xml
        && $local_xml ne ""
    )
    {
        return (
            "BLOCK_LOCAL_METADATA",
            $doi,
            "current repository DataCite metadata could not be prepared: "
                . $prepare_reason,
            $remote
        );
    }

    unless(
        defined $local_doi
        && lc( _normalise_doi($local_doi) )
            eq lc( _normalise_doi($doi) )
    )
    {
        return (
            "BLOCK_DOI_MISMATCH",
            $doi,
            "prepared local DOI differs from authenticated remote DOI",
            $remote
        );
    }

    #
    # detail=true in _datacite_member_get() supplies stored XML
    # as Base64.
    #
    my $remote_xml_b64 =
        $remote->{xml}
        || "";

    unless( $remote_xml_b64 ne "" )
    {
        return (
            "BLOCK_REMOTE_XML",
            $doi,
            "authenticated DataCite response does not contain stored XML",
            $remote
        );
    }

    my $remote_xml =
        decode_base64(
            $remote_xml_b64
        );

    unless( $remote_xml ne "" )
    {
        return (
            "BLOCK_REMOTE_XML",
            $doi,
            "stored DataCite XML could not be decoded",
            $remote
        );
    }

    my(
        $metadata_same,
        $different_properties,
        $compare_reason
    ) =
        $self->_compare_datacite_xml(
            $remote_xml,
            $local_xml
        );

    unless( $metadata_same )
    {
        $remote->{_datacite_different_properties} =
            $different_properties;

        return (
            "BLOCK_METADATA_DIFFERENCE",
            $doi,
            $compare_reason
                . "; automatic UPDATE_MODERN is refused",
            $remote
        );
    }

    my $remote_url =
        $remote->{url}
        || "";

    my $local_url =
        $dataobj->url()
        || "";

    $remote->{_datacite_local_url} =
        $local_url;

    $remote->{_datacite_metadata_compare} =
        "SAME";

    #
    # Nothing at all needs to be changed.
    #
    if(
        $remote_url ne ""
        && $remote_url eq $local_url
    )
    {
        return (
            "UPDATE_NOOP",
            $doi,
            "remote DataCite metadata and landing URL already match the repository; no PUT is required",
            $remote
        );
    }

    unless(
        $remote_url ne ""
        && $local_url ne ""
    )
    {
        return (
            "BLOCK_URL",
            $doi,
            "remote or local landing URL is empty",
            $remote
        );
    }

    #
    # Extremely narrow automatic update policy:
    #
    #     http://X  -> https://X
    #
    # with absolutely everything after the scheme identical.
    #
    my $remote_rest =
        $remote_url;

    my $local_rest =
        $local_url;

    unless(
        $remote_rest =~ s{^http://}{}i
        && $local_rest =~ s{^https://}{}i
        && $remote_rest eq $local_rest
    )
    {
        return (
            "BLOCK_URL_DIFFERENCE",
            $doi,
            "landing URLs differ by more than an exact http-to-https scheme upgrade; automatic update refused",
            $remote
        );
    }

    return (
        "UPDATE_URL_HTTPS_READY",
        $doi,
        "DataCite metadata are semantically identical; the only difference is an exact landing URL upgrade from HTTP to HTTPS",
        $remote
    );
}


sub prepare_datacite
{
    my( $self, $dataobj ) = @_;

    my(
        $mode,
        $doi,
        $reason
    ) =
        $self->classify_datacite(
            $dataobj
        );

    unless(
           $mode eq "MINT"
        || $mode eq "UPDATE"
    )
    {
        return (
            $mode,
            $doi,
            $reason,
            undef
        );
    }

    my $xml;

    my $ok = eval
    {
        $xml =
            $dataobj->export(
                "DataCiteXMLREST",
                doi => $doi
            );

        1;
    };

    unless( $ok )
    {
        my $error =
            $@ || "unknown export error";

        $error =~ s/\s+$//;

        return (
            "BLOCK_METADATA",
            $doi,
            "DataCiteXMLREST export failed: $error",
            undef
        );
    }

    unless(
        defined $xml
        && $xml ne ""
    )
    {
        return (
            "BLOCK_METADATA",
            $doi,
            "DataCiteXMLREST returned empty XML",
            undef
        );
    }

    my @xml_dois =
        (
            $xml =~
            m{<identifier\b[^>]*\bidentifierType\s*=\s*["']DOI["'][^>]*>([^<]+)</identifier>}gi
        );

    unless( @xml_dois == 1 )
    {
        return (
            "BLOCK_METADATA",
            $doi,
            "DataCite XML must contain exactly one DOI identifier; found "
                . scalar( @xml_dois ),
            undef
        );
    }

    my $xml_doi =
        _normalise_doi(
            $xml_dois[0]
        );

    unless(
        $xml_doi ne ""
        && lc( $xml_doi ) eq lc( $doi )
    )
    {
        return (
            "BLOCK_METADATA",
            $doi,
            "DataCite XML DOI mismatch: expected [$doi], found [$xml_doi]",
            undef
        );
    }

    return (
        $mode,
        $doi,
        $reason,
        $xml
    );
}




############################################################
# DataCite write authorisation
#
# SECURITY POLICY
#
# The userid is NEVER supplied by the caller.
# It is obtained exclusively from Repository->current_user().
#
# This deliberately means that:
#
#   - unauthenticated requests are denied;
#   - CLI/offline execution is denied;
#   - cron/event-queue execution is denied;
#   - admin/editor usertype alone grants nothing;
#   - only explicitly allowlisted numeric userids may write.
#
############################################################

sub _userid_is_write_authorised
{
    my( $self, $userid ) = @_;

    return 0
        unless defined $userid
        && $userid =~ /^[0-9]+$/;

    my $repository =
        $self->repository();

    return 0
        unless defined $repository;

    my $allowed =
        $repository->get_conf(
            "datacitedoi",
            "write_userids"
        );

    return 0
        unless ref( $allowed ) eq "HASH";

    return (
        exists $allowed->{$userid}
        && $allowed->{$userid}
    ) ? 1 : 0;
}


sub _write_authorised
{
    my( $self ) = @_;

    my $repository =
        $self->repository();

    return (
        0,
        undef,
        "missing repository"
    ) unless defined $repository;

    #
    # This is intentionally the ONLY source of the acting userid.
    #
    my $user =
        $repository->current_user();

    unless( defined $user )
    {
        return (
            0,
            undef,
            "DataCite write denied: no authenticated current EPrints user"
        );
    }

    my $userid =
        $user->id;

    unless(
        defined $userid
        && $userid =~ /^[0-9]+$/
    )
    {
        return (
            0,
            undef,
            "DataCite write denied: current EPrints user has no valid numeric userid"
        );
    }

    unless(
        $self->_userid_is_write_authorised(
            $userid
        )
    )
    {
        return (
            0,
            $userid,
            "DataCite write denied for EPrints userid $userid"
        );
    }

    return (
        1,
        $userid,
        "DataCite write authorised for EPrints userid $userid"
    );
}


############################################################
# Prepare REST payload for a NEW repository DOI.
#
# READ ONLY apart from the authenticated GET preflight.
#
# This function:
#   - requires MINT_READY from the authenticated Member API;
#   - generates current DataCite XML locally;
#   - verifies that preflight DOI and XML DOI agree;
#   - obtains the EPrint landing URL;
#   - Base64-encodes the XML;
#   - creates a JSON:API payload WITHOUT an event attribute.
#
# NO POST.
# NO PUT.
# NO DELETE.
#
# Returns:
#   mode, doi, reason, json_payload, xml, landing_url
############################################################

sub prepare_mint_rest_payload
{
    my( $self, $dataobj, $username, $password ) = @_;

    my(
        $pre_mode,
        $doi,
        $pre_reason,
        $remote
    ) =
        $self->preflight_datacite_authenticated(
            $dataobj,
            $username,
            $password
        );

    unless( $pre_mode eq "MINT_READY" )
    {
        return (
            "BLOCK",
            $doi,
            $pre_reason,
            undef,
            undef,
            undef
        );
    }

    my(
        $local_mode,
        $xml_doi,
        $xml_reason,
        $xml
    ) =
        $self->prepare_datacite(
            $dataobj
        );

    unless(
        $local_mode eq "MINT"
        && defined $xml
        && $xml ne ""
    )
    {
        return (
            "BLOCK",
            $doi,
            "DataCite XML preparation failed after MINT_READY: "
                . ($xml_reason || "unknown error"),
            undef,
            undef,
            undef
        );
    }

    unless(
        defined $xml_doi
        && lc($xml_doi) eq lc($doi)
    )
    {
        return (
            "BLOCK",
            $doi,
            "DOI mismatch between authenticated preflight [$doi] "
                . "and XML preparation [$xml_doi]",
            undef,
            undef,
            undef
        );
    }

    my $url =
        $dataobj->url();

    unless(
        defined $url
        && $url =~ m{^https?://}i
    )
    {
        return (
            "BLOCK",
            $doi,
            "invalid or missing landing URL",
            undef,
            $xml,
            $url
        );
    }

    my $payload = {
        data => {
            type => "dois",
            attributes => {
                doi => $doi,
                url => $url,
                xml => encode_base64(
                    encode("UTF-8", $xml),
                    ""
                ),
            },
        },
    };

    #
    # Safety invariant: this preparation function must NEVER
    # generate a state-changing DataCite event.
    #
    if(
        exists $payload->{data}->{attributes}->{event}
    )
    {
        return (
            "BLOCK",
            $doi,
            "internal safety failure: payload unexpectedly contains event",
            undef,
            $xml,
            $url
        );
    }

    my $json;

    my $ok = eval
    {
        $json = encode_json($payload);
        1;
    };

    unless( $ok )
    {
        my $error =
            $@ || "unknown JSON encoding error";

        $error =~ s/\s+$//;

        return (
            "BLOCK",
            $doi,
            "REST payload JSON encoding failed: $error",
            undef,
            $xml,
            $url
        );
    }

    return (
        "MINT_PAYLOAD_READY",
        $doi,
        "authenticated preflight passed and Draft REST payload was prepared; no write request was performed",
        $json,
        $xml,
        $url
    );
}



############################################################
# Create a NEW repository DOI in DataCite Draft state.
#
# WRITE OPERATION.
#
# SAFETY:
#   - first gate: authenticated EPrints current_user must be
#     explicitly allowlisted in write_userids;
#   - requires exact CREATE_DRAFT confirmation;
#   - performs a fresh authenticated MINT preflight;
#   - accepts only a fresh prepare_mint_rest_payload result;
#   - refuses any payload containing event;
#   - performs exactly ONE POST;
#   - never retries automatically;
#   - never publishes the DOI;
#   - does not write the DOI into the EPrints record.
#
############################################################

sub create_mint_draft
{
    my(
        $self,
        $dataobj,
        $username,
        $password,
        $confirmation
    ) = @_;

    #
    # HARD GATE 1:
    # this MUST remain the first operation in every write method.
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $self->_write_authorised();

    unless( $write_ok )
    {
        return (
            "BLOCK_UNAUTHORISED_USER",
            "",
            $write_reason,
            undef
        );
    }

    #
    # HARD GATE 2:
    # exact explicit confirmation.
    #
    unless(
        defined $confirmation
        && $confirmation eq "CREATE_DRAFT"
    )
    {
        return (
            "BLOCK_CONFIRMATION_REQUIRED",
            "",
            "explicit CREATE_DRAFT confirmation is required",
            undef
        );
    }

    #
    # Resolve the dedicated DataCite credential only AFTER both
    # local safety gates have passed.
    #
    my(
        $resolved_username,
        $resolved_password,
        $credential_error
    ) =
        $self->_datacite_credentials(
            $username,
            $password
        );

    unless( defined $resolved_username )
    {
        return (
            "BLOCK_CREDENTIALS",
            "",
            $credential_error
                || "DataCite authentication credentials unavailable",
            undef
        );
    }

    $username = $resolved_username;
    $password = $resolved_password;

    #
    # Fresh authenticated preflight + fresh XML/payload.
    #
    my(
        $payload_mode,
        $doi,
        $payload_reason,
        $json,
        $xml,
        $landing_url
    ) =
        $self->prepare_mint_rest_payload(
            $dataobj,
            $username,
            $password
        );

    unless(
        $payload_mode eq "MINT_PAYLOAD_READY"
        && defined $json
        && $json ne ""
    )
    {
        return (
            "BLOCK_PREFLIGHT",
            $doi,
            $payload_reason,
            undef
        );
    }

    #
    # Decode our own payload and verify its invariants immediately
    # before the POST.
    #
    my $decoded;

    my $decode_ok = eval
    {
        $decoded = decode_json( $json );
        1;
    };

    unless(
        $decode_ok
        && ref( $decoded ) eq "HASH"
        && ref( $decoded->{data} ) eq "HASH"
        && ref( $decoded->{data}->{attributes} ) eq "HASH"
    )
    {
        return (
            "BLOCK_PAYLOAD",
            $doi,
            "prepared REST payload cannot be decoded safely",
            undef
        );
    }

    my $attributes =
        $decoded->{data}->{attributes};

    if( exists $attributes->{event} )
    {
        return (
            "BLOCK_PAYLOAD",
            $doi,
            "Draft creation refused because REST payload contains an event attribute",
            undef
        );
    }

    my $payload_doi =
        _normalise_doi(
            $attributes->{doi} || ""
        );

    unless(
        $payload_doi ne ""
        && lc( $payload_doi ) eq lc( $doi )
    )
    {
        return (
            "BLOCK_PAYLOAD",
            $doi,
            "prepared REST payload DOI differs from authenticated preflight DOI",
            undef
        );
    }

    my $payload_url =
        $attributes->{url} || "";

    unless(
        defined $landing_url
        && $landing_url ne ""
        && $payload_url eq $landing_url
    )
    {
        return (
            "BLOCK_PAYLOAD",
            $doi,
            "prepared REST payload landing URL differs from the EPrint landing URL",
            undef
        );
    }

    my $repository =
        $self->repository();

    my $base =
        $repository->get_conf(
            "datacitedoi",
            "rest_apiurl"
        ) || "https://api.datacite.org";

    $base =~ s{/$}{};

    my $url =
        $base . "/dois";

    my $auth =
        "Basic "
        . encode_base64(
            $username . ":" . $password,
            ""
        );

    my $ua =
        LWP::UserAgent->new(
            timeout => 30,
            agent   => "EPrints-DataCite-REST-draft-create/1.0",
        );

    #
    # IMPORTANT:
    # exactly ONE POST and deliberately NO retry.
    #
    my $response =
        $ua->post(
            $url,
            "Content-Type" =>
                "application/vnd.api+json",
            "Accept" =>
                "application/vnd.api+json",
            "Authorization" =>
                $auth,
            Content =>
                $json
        );

    unless( $response->code == 201 )
    {
        return (
            "WRITE_FAILED",
            $doi,
            "DataCite POST returned HTTP "
                . $response->code
                . " "
                . $response->message,
            undef
        );
    }

    #
    # From this line onward the remote Draft HAS been created.
    #
    my $remote;

    my $parse_ok = eval
    {
        my $result =
            decode_json(
                $response->content
            );

        if(
            ref( $result ) eq "HASH"
            && ref( $result->{data} ) eq "HASH"
            && ref( $result->{data}->{attributes} ) eq "HASH"
        )
        {
            $remote =
                $result->{data}->{attributes};

            #
            # Preserve DataCite client ownership relationship
            # for post-write verification.
            #
            my $relationships =
                $result->{data}->{relationships};

            if(
                ref( $relationships ) eq "HASH"
                && ref( $relationships->{client} ) eq "HASH"
                && ref( $relationships->{client}->{data} ) eq "HASH"
            )
            {
                my $client_id =
                    $relationships->{client}->{data}->{id}
                    || "";

                if( $client_id ne "" )
                {
                    $remote->{_datacite_client_id} =
                        $client_id;
                }
            }
        }

        1;
    };

    unless(
        $parse_ok
        && defined $remote
    )
    {
        return (
            "DRAFT_CREATED_RESPONSE_UNREADABLE",
            $doi,
            "DataCite returned HTTP 201, so the Draft was created, but the response could not be parsed safely",
            undef
        );
    }

    my $remote_doi =
        _normalise_doi(
            $remote->{doi} || ""
        );

    unless(
        $remote_doi ne ""
        && lc( $remote_doi ) eq lc( $doi )
    )
    {
        return (
            "DRAFT_CREATED_RESPONSE_MISMATCH",
            $doi,
            "DataCite returned HTTP 201, but the DOI in the response differs from the requested DOI",
            $remote
        );
    }

    my $state =
        $remote->{state} || "";

    unless(
        lc( $state ) eq "draft"
    )
    {
        return (
            "DRAFT_CREATED_UNEXPECTED_STATE",
            $doi,
            "DataCite created the record but returned unexpected state '$state'",
            $remote
        );
    }

    my $remote_url =
        $remote->{url} || "";

    unless(
        $remote_url ne ""
        && $remote_url eq $landing_url
    )
    {
        return (
            "DRAFT_CREATED_URL_MISMATCH",
            $doi,
            "DataCite created the Draft but returned a landing URL different from the requested URL",
            $remote
        );
    }

    my $expected_client =
        $repository->get_conf(
            "datacitedoi",
            "client_id"
        ) || "";

    my $remote_client =
        $remote->{_datacite_client_id}
        || "";

    unless(
        $expected_client ne ""
        && $remote_client ne ""
        && lc( $remote_client ) eq lc( $expected_client )
    )
    {
        return (
            "DRAFT_CREATED_OWNERSHIP_UNVERIFIED",
            $doi,
            "DataCite created the Draft, but repository ownership could not be verified safely",
            $remote
        );
    }

    #
    # Safe audit record: no credential and no payload contents.
    #
    $repository->log(
        "[DataCiteEventREST WRITE] "
        . "action=create_draft "
        . "eprint=" . $dataobj->id . " "
        . "userid=$acting_userid "
        . "doi=[$doi] "
        . "state=draft"
    );

    return (
        "DRAFT_CREATED",
        $doi,
        "DataCite Draft created successfully by authorised EPrints userid $acting_userid; DOI has not been published or stored locally",
        $remote
    );
}


############################################################
# Diagnostic event only.
#
# NO NETWORK ACCESS.
############################################################

sub datacite_doi
{
    my( $self, $dataobj ) = @_;

    my $repository =
        $self->repository();

    my(
        $mode,
        $doi,
        $reason,
        $xml
    ) =
        $self->prepare_datacite(
            $dataobj
        );

    my $id =
        defined $dataobj
        ? $dataobj->id
        : "[unknown]";

    my $xml_chars =
        defined $xml
        ? length( $xml )
        : 0;

    $repository->log(
        "[DataCiteEventREST DIAGNOSTIC] "
        . "eprint=$id "
        . "mode=$mode "
        . "doi=[$doi] "
        . "xml_chars=$xml_chars "
        . "reason=[$reason]"
    );

    return undef;
}


1;
