#!/usr/bin/perl
use strict;
use warnings;

my $logfile = $ARGV[0] // "sim_output.log";

# Read the whole file as raw bytes, then normalize encoding.
open(my $fh, "<:raw", $logfile) or die "Cannot open $logfile: $!\n";
local $/;                      # slurp mode: read entire file at once
my $data = <$fh>;
close($fh);

# Strip UTF-16 (Windows PowerShell) or UTF-8 BOM and null bytes.
$data =~ s/^\xFF\xFE//;        # UTF-16 LE BOM
$data =~ s/^\xFE\xFF//;        # UTF-16 BE BOM
$data =~ s/^\xEF\xBB\xBF//;    # UTF-8 BOM
$data =~ s/\x00//g;            # drop null bytes from UTF-16

my ($passes, $fails, $coverage) = (0, 0, "N/A");
my @failing_tests;

foreach my $line (split /\r?\n/, $data) {
    if ($line =~ /(\d+)\s+passed,\s+(\d+)\s+failed/) {
        $passes = $1; $fails = $2;
    }
    if ($line =~ /COVERAGE:\s+([\d.]+)%/) {
        $coverage = $1;
    }
    if ($line =~ /^\[FAIL\]\s+(.*)/) {
        push @failing_tests, $1;
    }
}

print "=" x 55, "\n";
print " SSPC Verification - Triage Report\n";
print "=" x 55, "\n";
printf " Tests passed : %d\n", $passes;
printf " Tests failed : %d\n", $fails;
printf " Coverage     : %s%%\n", $coverage;
if (@failing_tests) {
    print "\n Failing cases:\n";
    print "   - $_\n" for @failing_tests;
} else {
    print "\n All tests passed.\n";
}
print "=" x 55, "\n";
exit($fails > 0 ? 1 : 0);
