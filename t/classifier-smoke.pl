#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

BEGIN {
    package EPrints::Plugin::Event;
    sub import {}
    sub repository { return $_[0]->{repository}; }
    $INC{'EPrints/Plugin/Event.pm'} = 1;
}

use lib "$FindBin::Bin/../lib/plugins";
require EPrints::Plugin::Event::DataCiteEventREST;

{
    package TestDataset;
    sub new { bless { fields => $_[1] }, $_[0] }
    sub has_field { $_[0]->{fields}->{$_[1]} ? 1 : 0 }
}
{
    package TestRepo;
    sub new { bless { conf => $_[1] }, $_[0] }
    sub get_conf {
        my ($self, @keys) = @_;
        my $value = $self->{conf};
        for my $key (@keys) {
            return undef unless ref($value) eq 'HASH' && exists $value->{$key};
            $value = $value->{$key};
        }
        return $value;
    }
}
{
    package TestEPrint;
    sub new { bless { id => $_[1], values => $_[2], dataset => $_[3] }, $_[0] }
    sub id { $_[0]->{id} }
    sub dataset { $_[0]->{dataset} }
    sub get_value { $_[0]->{values}->{$_[1]} }
    sub exists_and_set {
        my ($self, $field) = @_;
        return 0 unless exists $self->{values}->{$field};
        my $value = $self->{values}->{$field};
        return 0 unless defined $value;
        return scalar(@$value) > 0 if ref($value) eq 'ARRAY';
        return $value ne '';
    }
}

my $repo = TestRepo->new({
    datacitedoi => {
        eprintdoifield => 'doi',
        prefix => '10.1234',
        mint_prefix => '10.1234',
        repoid => 'repo',
        mint_all_types => 0,
        typesallowed => { article => 1 },
        duplicate_barrier_fields => [ 'id_number' ],
        eprintstatus => { archive => 1 },
    },
});

my $plugin = bless { repository => $repo },
    'EPrints::Plugin::Event::DataCiteEventREST';

my $dataset = TestDataset->new({
    map { $_ => 1 }
    qw(doi id_number eprint_status type title date creators_name editors_name)
});

sub base_values {
    return {
        eprint_status => 'archive',
        type => 'article',
        title => 'Example',
        date => '2026-01-01',
        creators_name => [ { family => 'Doe', given => 'Jane' } ],
        doi => '',
        id_number => '',
    };
}

sub check {
    my ($name, $modify, $expected) = @_;
    my $v = base_values();
    $modify->($v) if $modify;
    my $eprint = TestEPrint->new(42, $v, $dataset);
    my ($mode, $doi, $reason) = $plugin->classify_datacite($eprint);
    die "$name: expected [$expected], got [$mode]: $reason\n"
        unless $mode eq $expected;
    print "$name: $mode ($doi)\n";
}

check('mint', undef, 'MINT');
check('managed', sub { $_[0]->{doi} = '10.1234/repo/42' }, 'UPDATE');
check('wrong id', sub { $_[0]->{doi} = '10.1234/repo/99' }, 'BLOCK_WRONG_MANAGED_IDENTIFIER');
check('external barrier', sub { $_[0]->{id_number} = 'doi:10.9999/external' }, 'BLOCK_EXISTING_EXTERNAL_DOI');
check('managed historical', sub { $_[0]->{id_number} = '10.1234/repo/42' }, 'CHECK_LOCAL_MANAGED_IDENTIFIER');
check('type blocked', sub { $_[0]->{type} = 'dataset' }, 'BLOCK');

print "CLASSIFIER_SMOKE=OK\n";
