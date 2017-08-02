=head1 LICENSE

# Copyright [2017] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License,Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

ensembl_import_species_data.pl -

=head1 DESCRIPTION

  This script imports Ensembl gene, transcript and metadata data into the GIFTS database tables
  'ensembl_gene', 'ensembl_transcript' and 'ensembl_species_history'.

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::ApiVersion;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Mapper;
use Data::Dumper;
use Bio::EnsEMBL::GIFTS::DB qw(get_gifts_dbc);

#Create the registry
my $registry = "Bio::EnsEMBL::Registry";

#options that the user can set
my $species = 'homo_sapiens';
my $user;
my $release;

my $giftsdb_name;
my $giftsdb_host;
my $giftsdb_user;
my $giftsdb_pass;
my $giftsdb_port;

my $registry_host;
my $registry_user;
my $registry_pass;
my $registry_port;

GetOptions(
        'user=s' => \$user,
        'species=s' => \$species,
        'release=s' => \$release,
        'giftsdb_host=s' => \$giftsdb_host,
        'giftsdb_user=s' => \$giftsdb_user,
        'giftsdb_pass=s' => \$giftsdb_pass,
        'giftsdb_name=s' => \$giftsdb_name,
        'giftsdb_port=s' => \$giftsdb_port,
        'registry_host=s' => \$registry_host,
        'registry_user=s' => \$registry_user,
        'registry_pass=s' => \$registry_pass,
        'registry_port=s' => \$registry_port,
   );

if (!$giftsdb_name or !$giftsdb_host or !$giftsdb_user or !$giftsdb_pass or !$giftsdb_port) {
  die("Please specify the GIFTS database details with --giftsdb_host, --giftsdb_user, --giftsdb_pass, --giftsdb_name and --giftsdb_port.");
}

if (!$registry_host or !$registry_user or !$registry_pass or !$registry_port) {
  die("Please specify the registry host details with --registry_host, --registry_user, --registry_pass and --registry_port.");
}

if (!$release) {
  die "Please specify a release with --release\n";
}

print "Fetching $species,e$release\n";
print "Run by $user\n";

# Connect to the Ensembl database
my $registry = "Bio::EnsEMBL::Registry";
$registry->load_registry_from_db(
    -host => $registry_host,
    -user => $registry_user,
    -port => $registry_port,
    -pass => $registry_pass,
    -db_version => ''.$release
);

# Connect to the GIFTS database
my $dbc = get_gifts_dbc($giftsdb_name,$giftsdb_host,$giftsdb_user,$giftsdb_pass,$giftsdb_port);

# Get the slice_adaptor
my ($chromosome,$region_accession);
my $slice_adaptor = $registry->get_adaptor($species,'core','Slice');
my $slices = $slice_adaptor->fetch_all('toplevel');
my $meta_adaptor = $registry->get_adaptor($species,'core','MetaContainer');
my $ca = $registry->get_adaptor($species,'core','CoordSystem');
my $species_name = $meta_adaptor->get_scientific_name;
my $tax_id = $meta_adaptor->get_taxonomy_id;
my $ensdb_release = $meta_adaptor->schema_version;
my $assembly_name = $ca->fetch_all->[0]->version;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $load_time = ($year+1900)."-".($mon+1)."-".$mday;

# Primary keys
my $gene_id;
my $transcript_id;

my $gene_count=0;
my $transcript_count=0;

while (my $slice = shift @$slices) {
  # Fetch additional meta data on the slice
  $region_accession = $slice->seq_region_name;
  if ($slice->is_chromosome) {
    $chromosome = $slice->seq_region_name;
    if ($slice->get_all_synonyms('INSDC')->[0]) {
      $region_accession = $slice->get_all_synonyms('INSDC')->[0]->name;
    }
  }
  else {
    $chromosome = '';
  }

  my $sql_gene = "INSERT INTO ensembl_gene (ensg_id,gene_name,chromosome,region_accession,assembly_accession,species,deleted,ensembl_tax_id,seq_region_start,seq_region_end,seq_region_strand,biotype,ensembl_release,userstamp,time_loaded) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

  my $sql_transcript = "INSERT INTO ensembl_transcript (gene_id,enst_id,ccds_id,uniparc_accession,biotype,deleted,seq_region_start,seq_region_end,supporting_evidence,ensembl_release,userstamp,time_loaded,enst_version) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ";

  my $genes = $slice->get_all_Genes();
  while (my $gene = shift @$genes) {
    my $sth = $dbc->prepare($sql_gene);
    $sth->bind_param(1,$gene->stable_id);
    if ($gene->display_xref) {
      $sth->bind_param(2,$gene->display_xref->display_id);
    } else {
      $sth->bind_param(2,"");
    }
    $sth->bind_param(3,$chromosome);
    $sth->bind_param(4,$region_accession);
    $sth->bind_param(5,$assembly_name);
    $sth->bind_param(6,$species_name);
    $sth->bind_param(7,0);
    $sth->bind_param(8,$tax_id);
    $sth->bind_param(9,$gene->seq_region_start);
    $sth->bind_param(10,$gene->seq_region_end);
    $sth->bind_param(11,$gene->seq_region_strand);
    $sth->bind_param(12,$gene->biotype);
    $sth->bind_param(13,$release);
    $sth->bind_param(14,$user);
    $sth->bind_param(15,$load_time);
    $sth->execute() or die "Could not add gene entry to GIFTS database for ".$gene->stable_id."\n".$dbc->errstr;
    $gene_id = $sth->{mysql_insertid};
    $sth->finish();

    $gene_count++;
    foreach my $transcript (@{$gene->get_all_Transcripts}) {
      my ($start_exon,$end_exon,$start_exon_seq_offset,$end_exon_seq_offset,$start_exon_id,$end_exon_id);
      my $ccds = "";
      if ($transcript->ccds) {
        $ccds = $transcript->ccds->display_id;
      }
      ## Correct method for fetching transcript supporting features
      ## Will not work for human,as supporting features are stored on exon level
      #my $sfs = $transcript->get_all_supporting_features();
      #my $supporting_evidence;
      #foreach my $sf (@$sfs) {
      #  if ($sf->db_display_name =~ /Uniprot/) {
      #    $supporting_evidence = $sf->hseqname;
      #    last;
      #  }
      #}
      my $supporting_evidence = $transcript->get_all_DBLinks('Uniprot%')->[0];
      if (!$supporting_evidence) {
        $supporting_evidence = "";
      }
      my $uniparc = "";
      if (scalar(@{$transcript->get_all_DBLinks('UniParc')}) > 0) {
        $uniparc = $transcript->get_all_DBLinks('UniParc')->[0]->display_id;
      }

      my ($enst,$enst_version) = split(/\./,$transcript->stable_id_version);
      my $sth = $dbc->prepare($sql_transcript);
      $sth->bind_param(1,$gene_id);
      $sth->bind_param(2,$enst);
      $sth->bind_param(3,$ccds);
      $sth->bind_param(4,$uniparc);
      $sth->bind_param(5,$transcript->biotype);
      $sth->bind_param(6,0);
      $sth->bind_param(7,$transcript->seq_region_start);
      $sth->bind_param(8,$transcript->seq_region_end);
      $sth->bind_param(9,$supporting_evidence);
      $sth->bind_param(10,$release);
      $sth->bind_param(11,$user);
      $sth->bind_param(12,$load_time);
      $sth->bind_param(13,$enst_version);
      $sth->execute() or die "Could not add transcript entry to GIFTS database for ".$transcript->stable_id."\n".$dbc->errstr;
      $transcript_id = $sth->{mysql_insertid};
      $sth->finish();

      $transcript_count++;
    }
  }
}

# display results
print "Genes:".$gene_count."\n.";
print "Transcripts:".$transcript_count."\n.";

# write out the history
print "Adding entry to the ensembl_species_history table\n";
my $sql_history = "INSERT INTO ensembl_species_history (species,assembly_accession,ensembl_tax_id,ensembl_release,status) VALUES (?,?,?,?,?)";
my $sth = $dbc->prepare($sql_history);
$sth->bind_param(1,$species_name);
$sth->bind_param(2,$assembly_name);
$sth->bind_param(3,$tax_id);
$sth->bind_param(4,$release);
$sth->bind_param(5,"LOAD_COMPLETE");
$sth->execute() or die "Could not add history entry to GIFTS database:\n".$dbc->errstr;
$sth->finish();

print "Finished\n.";