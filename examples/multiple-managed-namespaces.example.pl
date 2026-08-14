# Example only: multiple managed DOI namespaces.
# This illustrates how a repository with both a current and a legacy suffix
# can reuse the generic Event plugin without hard-coding the institution in it.

$c->{datacitedoi}{prefix} = "10.EXAMPLE";
$c->{datacitedoi}{mint_prefix} = "10.EXAMPLE";
$c->{datacitedoi}{repoid} = "ORG/REPOSITORY";

$c->{datacitedoi}{canonical_doi} = sub
{
    my( $repo, $eprint ) = @_;
    return "10.EXAMPLE/ORG/REPOSITORY/" . $eprint->id;
};

$c->{datacitedoi}{managed_doi_eprintid} = sub
{
    my( $repo, $doi ) = @_;

    return $1 if $doi =~ m{^10\\.EXAMPLE/ORG/REPOSITORY/([0-9]+)$}i;
    return $1 if $doi =~ m{^10\\.EXAMPLE/repository-([0-9]+)$}i;

    return undef;
};

1;
