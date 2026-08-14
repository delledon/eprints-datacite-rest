# Generic DataCite Metadata Schema 4.7 mapping example for EPrints.
# Mandatory properties are mapped conservatively; optional properties are
# omitted when the corresponding EPrint field is absent or empty.

$c->{datacite_mapping_type} = sub
{
    my( $xml, $dataobj, $repo ) = @_;

    die "DataCite REST: missing eprint type on eprint " . $dataobj->id . "\n"
        unless $dataobj->exists_and_set("type");

    my $type = $dataobj->get_value("type") || "";
    $type =~ s/^\s+|\s+$//g;
    die "DataCite REST: empty eprint type on eprint " . $dataobj->id . "\n"
        if $type eq "";

    my $map = $repo->get_conf("datacitedoi", "typemap");
    my $mapped = ref($map) eq "HASH" ? $map->{$type} : undef;
    $mapped = [ $type, "Other" ] unless ref($mapped) eq "ARRAY" && @$mapped >= 2;

    return $xml->create_data_element(
        "resourceType", $mapped->[0], resourceTypeGeneral => $mapped->[1]
    );
};

$c->{datacite_mapping_creators} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    my $creators = $xml->create_element("creators");
    my $count = 0;

    if( $dataobj->exists_and_set("creators_name") )
    {
        my $names = $dataobj->get_value("creators_name");
        if( ref($names) eq "ARRAY" )
        {
            for my $name (@$names)
            {
                next unless ref($name) eq "HASH";
                my $family = $name->{family} || "";
                my $given  = $name->{given}  || "";
                $family =~ s/^\s+|\s+$//g;
                $given  =~ s/^\s+|\s+$//g;
                next if $family eq "" && $given eq "";

                my $display = $family ne "" && $given ne ""
                    ? "$family, $given" : ($family ne "" ? $family : $given);

                my $creator = $xml->create_element("creator");
                $creator->appendChild(
                    $xml->create_data_element("creatorName", $display, nameType => "Personal")
                );
                $creator->appendChild($xml->create_data_element("givenName", $given))
                    if $given ne "";
                $creator->appendChild($xml->create_data_element("familyName", $family))
                    if $family ne "";
                $creators->appendChild($creator);
                $count++;
            }
        }
    }

    my $corp_fields = $repo->get_conf("datacitedoi", "corporate_creator_fields");
    $corp_fields = [ "corp_creators", "corporate_creators" ]
        unless ref($corp_fields) eq "ARRAY";

    for my $field (@$corp_fields)
    {
        next unless $dataobj->dataset->has_field($field);
        next unless $dataobj->exists_and_set($field);
        my $values = $dataobj->get_value($field);
        $values = [ $values ] unless ref($values) eq "ARRAY";
        for my $value (@$values)
        {
            next unless defined $value;
            $value =~ s/^\s+|\s+$//g;
            next if $value eq "";
            my $creator = $xml->create_element("creator");
            $creator->appendChild(
                $xml->create_data_element("creatorName", $value, nameType => "Organizational")
            );
            $creators->appendChild($creator);
            $count++;
        }
    }

    my $type = $dataobj->exists_and_set("type")
        ? ($dataobj->get_value("type") || "") : "";
    my $editor_types = $repo->get_conf("datacitedoi", "editor_fallback_types");
    $editor_types = { book => 1 } unless ref($editor_types) eq "HASH";

    if( $count == 0 && $editor_types->{$type}
        && $dataobj->exists_and_set("editors_name") )
    {
        my $names = $dataobj->get_value("editors_name");
        if( ref($names) eq "ARRAY" )
        {
            for my $name (@$names)
            {
                next unless ref($name) eq "HASH";
                my $family = $name->{family} || "";
                my $given  = $name->{given}  || "";
                $family =~ s/^\s+|\s+$//g;
                $given  =~ s/^\s+|\s+$//g;
                next if $family eq "" && $given eq "";
                my $display = $family ne "" && $given ne ""
                    ? "$family, $given" : ($family ne "" ? $family : $given);
                my $creator = $xml->create_element("creator");
                $creator->appendChild(
                    $xml->create_data_element("creatorName", $display, nameType => "Personal")
                );
                $creator->appendChild($xml->create_data_element("givenName", $given))
                    if $given ne "";
                $creator->appendChild($xml->create_data_element("familyName", $family))
                    if $family ne "";
                $creators->appendChild($creator);
                $count++;
            }
        }
    }

    die "DataCite REST: no usable Creator for eprint " . $dataobj->id . "\n"
        unless $count > 0;

    return $creators;
};

$c->{datacite_mapping_title} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    die "DataCite REST: missing title on eprint " . $dataobj->id . "\n"
        unless $dataobj->exists_and_set("title");
    my $title = $dataobj->get_value("title") || "";
    $title =~ s/^\s+|\s+$//gs;
    die "DataCite REST: empty title on eprint " . $dataobj->id . "\n"
        if $title eq "";
    my $titles = $xml->create_element("titles");
    $titles->appendChild($xml->create_data_element("title", $title));
    return $titles;
};

$c->{datacite_mapping_publisher} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    my $publisher = $dataobj->exists_and_set("publisher")
        ? ($dataobj->get_value("publisher") || "") : "";
    $publisher =~ s/^\s+|\s+$//g;
    $publisher = $repo->get_conf("datacitedoi", "publisher_fallback") || ""
        if $publisher eq "";
    die "DataCite REST: no Publisher for eprint " . $dataobj->id . "\n"
        if $publisher eq "";
    return $xml->create_data_element("publisher", $publisher);
};

$c->{datacite_mapping_date} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    my $date = $dataobj->exists_and_set("date")
        ? ($dataobj->get_value("date") || "") : "";
    my $year = $date =~ /^([0-9]{4})(?:\b|-)/ ? $1 : undef;
    die "DataCite REST: no valid PublicationYear in date [$date] for eprint "
        . $dataobj->id . "\n" unless defined $year;
    return $xml->create_data_element("publicationYear", $year);
};

$c->{datacite_mapping_language} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    return undef unless $dataobj->dataset->has_field("language");
    return undef unless $dataobj->exists_and_set("language");
    my $language = $dataobj->get_value("language") || "";
    $language =~ s/^\s+|\s+$//g;
    return undef if $language eq "";
    return $xml->create_data_element("language", $language);
};

$c->{datacite_mapping_keywords} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    return undef unless $dataobj->dataset->has_field("keywords");
    return undef unless $dataobj->exists_and_set("keywords");
    my $value = $dataobj->get_value("keywords") || "";
    $value =~ s/^\s+|\s+$//gs;
    return undef if $value eq "";
    my $subjects = $xml->create_element("subjects");
    $subjects->appendChild($xml->create_data_element("subject", $value));
    return $subjects;
};

$c->{datacite_mapping_abstract} = sub
{
    my( $xml, $dataobj, $repo ) = @_;
    return undef unless $dataobj->dataset->has_field("abstract");
    return undef unless $dataobj->exists_and_set("abstract");
    my $value = $dataobj->get_value("abstract") || "";
    $value =~ s/^\s+|\s+$//gs;
    return undef if $value eq "";
    my $descriptions = $xml->create_element("descriptions");
    $descriptions->appendChild(
        $xml->create_data_element("description", $value, descriptionType => "Abstract")
    );
    return $descriptions;
};

1;
