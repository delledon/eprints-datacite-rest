package EPrints::Plugin::Export::DataCiteXMLREST;

use EPrints::Plugin::Export::Feed;

@ISA = ('EPrints::Plugin::Export::Feed');

use strict;

sub new
{
    my ($class, %opts) = @_;

    my $self = $class->SUPER::new(%opts);

    $self->{name} = 'DataCite XML - REST';
    $self->{accept} = [ 'dataobj/eprint' ];
    $self->{visible} = 'all';
    $self->{suffix} = '.xml';
    $self->{mimetype} = 'application/xml; charset=utf-8';
    $self->{arguments}->{doi} = undef;

    return $self;
}

sub output_dataobj
{
    my ($self, $dataobj, %opts) = @_;

    my $repo = $self->{repository};
    my $xml = $repo->xml;

    my $entry = $xml->create_element(
        "resource",
        xmlns => $repo->get_conf("datacitedoi", "xmlns"),
        "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:schemaLocation" =>
            $repo->get_conf("datacitedoi", "schemaLocation")
    );

    #
    # DOI source precedence:
    #
    # 1. Explicit DOI supplied by DataCiteEventREST.
    # 2. DOI already stored in the configured dedicated DOI field.
    # 3. Otherwise fail.
    #
    # This exporter NEVER creates or recalculates a DOI.
    #
    my $doi_field =
        $repo->get_conf(
            "datacitedoi",
            "eprintdoifield"
        ) || "doi";

    my $thisdoi;

    if(
        defined $opts{doi}
        && $opts{doi} ne ""
    )
    {
        $thisdoi = $opts{doi};
    }
    elsif(
        $dataobj->exists_and_set(
            $doi_field
        )
    )
    {
        $thisdoi =
            $dataobj->get_value(
                $doi_field
            );
    }
    else
    {
        die "DataCiteXMLREST: no DOI supplied and no DOI stored for eprint "
            . $dataobj->id . "\n";
    }

    $thisdoi =~ s/^\s+//;
    $thisdoi =~ s/\s+$//;
    $thisdoi =~ s/^doi:\s*//i;
    $thisdoi =~ s!^https?://(?:dx\.)?doi\.org/!!i;

    die "DataCiteXMLREST: empty DOI after normalisation for eprint "
        . $dataobj->id . "\n"
        if $thisdoi eq "";

    $entry->appendChild(
        $xml->create_data_element(
            "identifier",
            $thisdoi,
            identifierType => "DOI"
        )
    );

    #
    # DataCite XML element order is schema-defined.
    #
    my @mapping_order = qw(
        datacite_mapping_creators
        datacite_mapping_title
        datacite_mapping_publisher
        datacite_mapping_date
        datacite_mapping_language
        datacite_mapping_keywords
        datacite_mapping_type
        datacite_mapping_repo_link
        datacite_mapping_rights_from_docs
        datacite_mapping_abstract
        datacite_mapping_geographic_cover
        datacite_mapping_funders
    );

    foreach my $mapping_fn (@mapping_order)
    {
        next unless $repo->can_call($mapping_fn);

        my $mapped =
            $repo->call(
                $mapping_fn,
                $xml,
                $dataobj,
                $repo
            );

        $entry->appendChild($mapped)
            if defined $mapped;
    }

    return
        '<?xml version="1.0" encoding="UTF-8"?>'
        . "\n"
        . $xml->to_string($entry);
}

1;
