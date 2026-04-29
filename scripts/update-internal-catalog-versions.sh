#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-.}"
catalog_file="${repo_root%/}/gradle/libs.versions.toml"

if [ ! -f "$catalog_file" ]; then
    echo "Skipping internal dependency update because $catalog_file does not exist."
    exit 0
fi

perl - "$catalog_file" <<'PERL'
use strict;
use warnings;
use File::Temp qw(tempfile);

my $catalog_file = shift @ARGV;
my $maven_local = "$ENV{HOME}/.m2/repository";
my @internal_prefixes = ('sollecitom');

open my $in, '<', $catalog_file or die "Unable to read $catalog_file: $!";
my @lines = <$in>;
close $in;

my %version_lines;
my %current_versions;
my %references;
my $section = '';

for my $index (0 .. $#lines) {
    my $line = $lines[$index];
    if ($line =~ /^\s*\[([^\]]+)\]\s*$/) {
        $section = $1;
        next;
    }

    if ($section eq 'versions') {
        if ($line =~ /^(\s*)([A-Za-z0-9_.-]+)(\s*=\s*)"([^"]+)"(\s*(?:#.*)?)$/) {
            $version_lines{$2} = $index;
            $current_versions{$2} = $4;
        }
        next;
    }

    if ($section eq 'libraries') {
        if ($line =~ /^\s*[A-Za-z0-9_.-]+\s*=\s*\{.*\bmodule\s*=\s*"([^":]+):([^"]+)".*\bversion\.ref\s*=\s*"([^"]+)".*\}\s*(?:#.*)?$/) {
            my ($group, $artifact, $version_ref) = ($1, $2, $3);
            next unless matches_internal($group);
            $references{$version_ref} ||= {};
            $references{$version_ref}->{"$group:$artifact"} = 1;
        }
        next;
    }

    if ($section eq 'plugins') {
        if ($line =~ /^\s*[A-Za-z0-9_.-]+\s*=\s*\{.*\bid\s*=\s*"([^"]+)".*\bversion\.ref\s*=\s*"([^"]+)".*\}\s*(?:#.*)?$/) {
            my ($plugin_id, $version_ref) = ($1, $2);
            next unless matches_internal($plugin_id);
            $references{$version_ref} ||= {};
            $references{$version_ref}->{"$plugin_id:$plugin_id.gradle.plugin"} = 1;
        }
        next;
    }
}

my @applied_updates;

for my $version_ref (sort keys %references) {
    next unless exists $current_versions{$version_ref};

    my %available;
    for my $coordinate (sort keys %{ $references{$version_ref} }) {
        my ($group, $artifact) = split /:/, $coordinate, 2;
        my $resolved = latest_published_version($group, $artifact);
        $available{$resolved} = 1 if defined $resolved;
    }

    next unless %available;

    my @versions = sort { compare_versions($a, $b) } keys %available;
    die "Inconsistent published versions for internal version ref '$version_ref': " . join(', ', @versions) . "\n"
        if @versions > 1;

    my $target = $versions[0];
    my $current = $current_versions{$version_ref};
    next unless compare_versions($target, $current) > 0;

    my $line_index = $version_lines{$version_ref};
    $lines[$line_index] =~ s/^(\s*\Q$version_ref\E\s*=\s*)"[^"]+"(\s*(?:#.*)?)$/$1"$target"$2/;
    $current_versions{$version_ref} = $target;
    push @applied_updates, "$version_ref: $current -> $target";
}

if (!@applied_updates) {
    print "No internal dependency updates available.\n";
    exit 0;
}

my ($tmp_fh, $tmp_name) = tempfile("${catalog_file}.tmp.XXXXXX", UNLINK => 0);
print {$tmp_fh} @lines or die "Unable to write $tmp_name: $!";
close $tmp_fh or die "Unable to close $tmp_name: $!";
rename $tmp_name, $catalog_file or die "Unable to replace $catalog_file: $!";

print "$_\n" for @applied_updates;

sub matches_internal {
    my ($value) = @_;
    for my $prefix (@internal_prefixes) {
        return 1 if $value eq $prefix;
        return 1 if index($value, "$prefix.") == 0;
        return 1 if index($value, "$prefix-") == 0;
    }
    return 0;
}

sub latest_published_version {
    my ($group, $artifact) = @_;
    my $group_path = $group;
    $group_path =~ s/\./\//g;
    my $metadata = "$maven_local/$group_path/$artifact/maven-metadata-local.xml";
    return undef unless -f $metadata;

    open my $meta, '<', $metadata or die "Unable to read $metadata: $!";
    local $/;
    my $xml = <$meta>;
    close $meta;

    my @candidates;
    push @candidates, $1 if $xml =~ m{<release>([^<]+)</release>};
    push @candidates, $1 if $xml =~ m{<latest>([^<]+)</latest>};
    push @candidates, ($xml =~ m{<version>([^<]+)</version>}g);

    my %seen;
    @candidates = grep { defined $_ && $_ ne '' && $_ !~ /-SNAPSHOT$/ && !$seen{$_}++ } @candidates;
    return undef unless @candidates;

    @candidates = sort { compare_versions($a, $b) } @candidates;
    return $candidates[-1];
}

sub compare_versions {
    my ($left, $right) = @_;
    my @left_parts = split /\./, $left;
    my @right_parts = split /\./, $right;
    my $max = @left_parts > @right_parts ? scalar @left_parts : scalar @right_parts;

    for my $index (0 .. $max - 1) {
        my $left_part = defined $left_parts[$index] ? $left_parts[$index] : 0;
        my $right_part = defined $right_parts[$index] ? $right_parts[$index] : 0;

        my ($left_num, $left_suffix) = $left_part =~ /^(\d+)(.*)$/;
        my ($right_num, $right_suffix) = $right_part =~ /^(\d+)(.*)$/;
        $left_num = defined $left_num ? $left_num : 0;
        $right_num = defined $right_num ? $right_num : 0;

        my $numeric = $left_num <=> $right_num;
        return $numeric if $numeric != 0;

        my $suffix = ($left_suffix // '') cmp ($right_suffix // '');
        return $suffix if $suffix != 0;
    }

    return 0;
}
PERL
