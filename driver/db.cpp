/*
 */

#include <iostream>
#include <fstream>
#include <string>
#include <cstring>
#include <sstream>
#include <list>
#include <set>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cfloat>
#include <cmath>
#include "fft_accelerator.h"
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>

#define NFFT 512
#define NBINS 6
#define BIN0 0
#define BIN1 10
#define BIN2 20
#define BIN3 40
#define BIN4 80
#define BIN5 160
#define BIN6 240

#define PRUNING_COEF 1.4f
#define PRUNING_TIME_WINDOW 500
#define NORM_POW 1.0f
#define STD_DEV_COEF 1.25
#define T_ZONE 4

struct peak_raw {
	float ampl;
	uint16_t freq;
	uint16_t time;
};

struct peak {
	uint16_t freq;
	uint16_t time;
};

struct fingerprint {
	uint16_t anchor;
	uint16_t point;
	uint16_t delta;
};

struct song_data {
	std::string song_name;
	uint16_t time_pt;
	uint16_t song_ID;
};

struct hash_pair {
	uint64_t fingerprint;
	struct song_data value;
};

struct count_ID {
	std::string song;
	int count;
	int num_hashes;
};

struct database_info{
	std::string song_name;
	uint16_t song_ID;
	int hash_count;
};

void write_constellation(std::list<peak> pruned, std::string filename);

std::list<hash_pair> hash_create(std::string song_name, uint16_t song_ID);

std::list<hash_pair> generate_fingerprints(std::list<peak> pruned, 
	std::string song_name, uint16_t song_ID);

std::unordered_map<uint16_t, count_ID> identify_sample(
	const std::list<hash_pair> & sample_prints, 
	const std::unordered_multimap<uint64_t, song_data> & database,
	std::list<database_info> song_list);

std::list<peak> generate_constellation_map(std::vector<std::vector<float>> fft, int nfft);

std::list<peak> read_constellation(std::string filename);

std::vector<std::vector<float>> get_fft_from_audio(float sec);

std::list<hash_pair> hash_create_from_audio(float sec);

std::list<peak> create_map_from_audio(float sec);

float score(const struct count_ID &c) {
	return ((float) c.count)/std::pow(c.num_hashes, NORM_POW);	
}

bool sortByScore(const struct count_ID &lhs, const struct count_ID &rhs) { 
	return lhs.count == rhs.count ? score(lhs) > score(rhs) : lhs.count > rhs.count;
}

int fft_accelerator_fd;

int main()
{
	/*
	 * Assumes fft spectrogram files are availible at ./song_name, and that
	 * song_list.txt exists and contains a list of the song names.
	 */
	
	std::unordered_multimap<uint64_t, song_data> db;
	std::list<database_info> song_names;
	std::unordered_map<uint16_t, count_ID> results;
	struct hash_pair pair;
	std::pair<uint64_t, song_data> temp_db;
	struct database_info temp_db_info;
	std::string temp_match;
	std::string temp_s;
	
	std::string output;
	int hash_count;
	
	std::fstream file;
	std::string line;
	std::vector<std::string> song_file_list;
	
	uint16_t num_db = 0;	

	// open device:
	static const char filename[] = "/dev/fft_accelerator";
	if( (fft_accelerator_fd = open(filename, O_RDWR)) == -1) {
		std::cerr << "could not open " << filename << std::endl;
		return -1;
	}
	

	std::cout << "Full database completed \n\n" << std::endl;

	
	while(true)
	{
		std::string song_name;
		std::cout << "Ready to identify. Press ENTER to identify the song playing.\n";
		std::cin >> song_name;

		temp_s = line; 
		std::list<peak> pruned;
		// identify = hash_create_noise(temp_s, num_db);
		pruned = create_map_from_audio(200);
		std::cout << "Done listening.\n"; 
		write_constellation(pruned, song_name + "_board.realpeak");
		std::cout << "Wrote constellation map for " << song_name << ".\n";
	}
		


	
	return 0;
}


std::unordered_map<uint16_t, count_ID> identify_sample(
	const std::list<hash_pair> & sample_prints, 
	const std::unordered_multimap<uint64_t, song_data> & database,
	std::list<database_info> song_list)
{
	std::cout << "call to identify" << std::endl;
	
	std::unordered_map<uint16_t, count_ID> results;
	//new database, keys are songIDs concatenated with time anchor
	//values are number of appearances, if 5 we've matched
	std::unordered_map<uint64_t, uint8_t> db2;
	uint64_t new_key;
	uint16_t identity;

	for(std::list<database_info>::iterator iter = song_list.begin(); 
		iter != song_list.end(); ++iter){	
		//scaling may no longer be necessary, but currently used
		results[iter->song_ID].num_hashes = iter->hash_count;
		results[iter->song_ID].song = iter->song_name;
		//set count to zero, will now be number of target zones matched
		results[iter->song_ID].count = 0;

	}	

	//for fingerpint in sampleFingerprints
	for(auto iter = sample_prints.begin(); 
		iter != sample_prints.end(); ++iter){	
		
	    // get all the entries at this hash location
	    const auto & ret = database.equal_range(iter->fingerprint);

	    //lets insert the song_ID, time anchor pairs in our new database
	    for(auto  it = ret.first; it != ret.second; ++it){
		  
		    new_key = it->second.song_ID;
		    new_key = new_key << 16;
		    new_key |= it->second.time_pt;
		    new_key = new_key << 16;
		    new_key |= iter->value.time_pt;

		    db2[new_key]++;
	    }
		
	}
	// second database is fully populated


	//adds to their count in the results structure, which is returned
	for(std::unordered_map<uint64_t,uint8_t>::iterator
			    it = db2.begin(); it != db2.end(); ++it){
		
		//full target zone matched
		if(it->second >= T_ZONE)
		{
			//std::cout << it->second << std::endl;
			identity = it->first >> 32;
			results[identity].count += (int) (it->second);
		}
	}    

	return results;

}

std::list<hash_pair> hash_create(std::string song_name, uint16_t song_ID)
{	
	std::cout << "call to hash_create" << std::endl;
	std::cout << "Song ID = " << song_ID << std::endl; 

	std::list<peak> pruned_peaks;
	pruned_peaks = read_constellation(song_name);			
	
	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name, song_ID);

	return hash_entries;
}


std::list<peak> create_map_from_audio(float sec)
{	
	std::list<peak> pruned_peaks;
	std::cout << "call to create_map_from_audio" << std::endl;
	std::vector<std::vector<float>> fft;
	fft = get_fft_from_audio(sec);	
	pruned_peaks = generate_constellation_map(fft, NFFT);
	return pruned_peaks;
}

std::list<hash_pair> hash_create_from_audio(float sec)
{	
	uint16_t song_ID = 0;
	std::string song_name = "AUDIO";
	std::cout << "call to hash_create_from_audio" << std::endl;
	std::vector<std::vector<float>> fft;
	fft = get_fft_from_audio(sec);	

	std::list<peak> pruned_peaks;
	pruned_peaks = generate_constellation_map(fft, NFFT);

	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name, song_ID);

	return hash_entries;
}

std::list<hash_pair> generate_fingerprints(std::list<peak> pruned, 
	std::string song_name, uint16_t song_ID)
{
	std::list<hash_pair> fingerprints;
	struct fingerprint f;
	struct song_data sdata;
	struct hash_pair entry;
	uint16_t target_zone_t;
	uint64_t template_print;
	struct peak other_point;
	struct peak anchor_point;

	int target_offset = 2;

	target_zone_t = T_ZONE;
	

	for(std::list<peak>::iterator it = pruned.begin(); 
	 std::next(it, target_zone_t + target_offset) != pruned.end(); it++){

		anchor_point= *it;
	
		for(uint16_t i = 1; i <= target_zone_t; i++){
			
			other_point = *(std::next(it, i + target_offset));
			
			f.anchor = anchor_point.freq;
			f.point = other_point.freq;
			f.delta	= other_point.time - anchor_point.time;
			
			sdata.song_name = song_name;
			sdata.time_pt = anchor_point.time;
			sdata.song_ID = song_ID;

			template_print = f.anchor;
			template_print = template_print << 16;
			template_print |= f.point;
			template_print = template_print << 16;
			template_print |= f.delta;

			entry.fingerprint = template_print;
			entry.value = sdata;
	
			fingerprints.push_back(entry);
		}
	}	

	return fingerprints;
}


uint32_t sec_to_samples(float sec) {
	return (int) sec*(SAMPLING_FREQ/DOWN_SAMPLING_FACTOR); 
}

float samples_to_sec(uint32_t samples) {
	return  ((float) samples)/SAMPLING_FREQ; 
}

float ampl2float(ampl_t fixed) {
	// divide by 2^(fixed point accuracy) 2^7.
	return ((float) fixed) / std::pow(2.0, AMPL_FRACTIONAL_BITS);
}

#define ERR_IO 0xFFFFFFFFFFFFFFFFu
#define ERR_NVALID 0xFFFFFFFFFFFFFFFEu

uint64_t get_sample(std::vector<float> & fft) {
	fft_accelerator_arg_t vla;
	fft_accelerator_fft_t fft_struct;
	vla.fft_struct = &fft_struct;

	fft.clear();
	fft.reserve(N_FREQUENCIES);

	if (ioctl(fft_accelerator_fd, FFT_ACCELERATOR_READ_FFT, &vla)) {
		perror("ioctl(FFT_ACCELERATOR_READ_FFT) failed");
		return ERR_IO;
	}
	if(!fft_struct.valid) {
		return ERR_NVALID;
	}
	for (int i = 0; i < N_FREQUENCIES; i++) {
		//std::cout << ampl2float(fft_struct.fft[i]) << " ";
		fft.push_back(ampl2float(fft_struct.fft[i]));
	}
		//std::cout << std::endl;
	return fft_struct.time;
}


std::vector<std::vector<float>> get_fft_from_audio(float sec) {
	uint32_t samples = sec_to_samples(sec);
	std::cout << samples << std::endl;
	std::vector<std::vector<float>> spec;
	spec.reserve(N_FREQUENCIES);
	for (int i = 0; i < N_FREQUENCIES; i++) {
		std::vector<float> vec;
		vec.reserve(samples);
		spec.push_back(vec);
	}
	std::vector<float> fft_temp;
	uint64_t time;

	for (uint32_t i = 0; i < samples; i++) {
		time = get_sample(fft_temp);
		//this assumes we miss nothing
	
		for(uint32_t j = 0; j < N_FREQUENCIES; j++){
			//std::cout << fft_temp[j] << " ";
			spec[j].push_back(std::abs(fft_temp[j]));
		}	
			//std::cout << std::endl;
		if (time == ERR_IO || time == ERR_NVALID) {
			std::cout << "Could not get audio fft\n";
		        // spec[0].size < samples
			return spec;
		}
		 //copy contents of fft_temp into spec[i], averaging if there are missed times.

	}
	return spec;
}

// Eitan's re-write:

inline int freq_to_bin(uint16_t freq) {
	if (freq <  BIN1) 
		return 1;
	if (freq <  BIN2) 
		return 2;
	if (freq <  BIN3) 
		return 3;
	if (freq <  BIN4) 
		return 4;
	if (freq <  BIN5) 
		return 5;
	if (freq <  BIN6) 
		return 6;
	return 0;
}

std::list<peak_raw> get_raw_peaks(std::vector<std::vector<float>> fft, int nfft)
{
    std::list<peak_raw> peaks;
    uint16_t size_in_time;
    
    size_in_time = fft[0].size();
    for(uint16_t j = 1; j < size_in_time-2; j++){
	// WARNING not parametrized by NBINS
	float max_ampl_by_bin[NBINS + 1] = {FLT_MIN, FLT_MIN, FLT_MIN, FLT_MIN, FLT_MIN, FLT_MIN, FLT_MIN};  
    	struct peak_raw max_peak_by_bin[NBINS + 1] = {};
        for(uint16_t i = 0; i < fft.size() - 1; i++){
            if(     fft[i][j] > fft[i][j-1]                      && //west
    	            fft[i][j] > fft[i][j+1]                      && //east
    	            (i < 1           || fft[i][j] > fft[i-1][j]) && //north
    	            (i >= fft.size() || fft[i][j] > fft[i+1][j])) { //south
		if (fft[i][j] > max_ampl_by_bin[freq_to_bin(i)]) {
		    max_ampl_by_bin[freq_to_bin(i)] = fft[i][j];
		    max_peak_by_bin[freq_to_bin(i)].freq = i;
		    max_peak_by_bin[freq_to_bin(i)].ampl = fft[i][j];
		    max_peak_by_bin[freq_to_bin(i)].time = j;
		}
            }
        }
	for (int k = 1; k <= NBINS; k++) {
	    if (max_peak_by_bin[k].time != 0) {
                peaks.push_back(max_peak_by_bin[k]);
	    }
	}
    }
    return peaks;
}

std::list<peak> prune_in_time(std::list<peak_raw> unpruned_peaks) {
	int time = 0;
	float num[NBINS + 1] = { };  
	float den[NBINS + 1] = { };  
	float dev[NBINS + 1] = { };
	int bin;
	unsigned int bin_counts[NBINS + 1] = { };  
	unsigned int bin_prune_counts[NBINS + 1] = { };  
	std::list<peak> pruned_peaks;
	auto add_iter = unpruned_peaks.cbegin();
	auto dev_iter = unpruned_peaks.cbegin();
	for(auto avg_iter = unpruned_peaks.cbegin(); add_iter != unpruned_peaks.cend(); ){
	
		if (avg_iter->time <= time + PRUNING_TIME_WINDOW && avg_iter != unpruned_peaks.cend()) {
			bin = freq_to_bin(avg_iter->freq);
			den[bin]++;
			num[bin] += avg_iter->ampl;
			avg_iter++;
		} else {

			while(dev_iter != avg_iter){
				if (dev_iter->time <= time + PRUNING_TIME_WINDOW 
					&& dev_iter != unpruned_peaks.cend()) {
				
					bin = freq_to_bin(dev_iter->freq);
					if(den[bin]){
						dev[bin] += pow(dev_iter->ampl - num[bin]/den[bin], 2);
					}
					else{
						dev[bin] = den[bin];
					}
				}
				dev_iter++;	
			}
			for (int i = 1; i <= NBINS; i++)
			{
				if(den[i]){
					dev[i] = sqrt(dev[i]/den[i]);
				}
				//std::cout << dev[i] << " ";
			}
			//std::cout << std::endl;
			while (add_iter != avg_iter) {
				bin = freq_to_bin(add_iter->freq);
				if (den[bin] && add_iter->ampl > STD_DEV_COEF*dev[bin] + num[bin]/den[bin]  ) {
					pruned_peaks.push_back({add_iter->freq, add_iter->time});
					bin_counts[freq_to_bin(add_iter->freq)]++;
				} else {
					bin_prune_counts[freq_to_bin(add_iter->freq)]++;
				}
				add_iter++;
			}
			memset(num, 0, sizeof(num));
			memset(den, 0, sizeof(den));
			time += PRUNING_TIME_WINDOW;
		}
	}
	for (int i = 1; i <= NBINS; i++) {
		std::cout << "bin " << i << ": " << bin_counts[i] << "|  pruned: " << bin_prune_counts[i] << std::endl;
	}
	return pruned_peaks;
}
				


std::list<peak> generate_constellation_map(std::vector<std::vector<float>> fft, int nfft)
{
	std::list<peak_raw> unpruned_map;
	unpruned_map = get_raw_peaks(fft, nfft);
	return prune_in_time(unpruned_map);
}

std::list<peak> read_constellation(std::string filename){

	std::ifstream fin;
	std::list<peak> constellation;
	uint32_t peak_32;
	struct peak temp;
	std::streampos size;
  	char * memblock;
	int i;
	
	fin.open(filename+"_48.magpeak", std::ios::binary | std::ios::in 
			| std::ios::ate);

	i = 0;
      	if (fin.is_open())
       	{
	     size = fin.tellg(); 
	     memblock = new char [size];
	     
	     fin.seekg (0, std::ios::beg);
	     fin.read (memblock, size);
	     fin.close();
	     
	     while(i < size)
	     {

		    peak_32 = *(uint32_t *)(memblock+i);
		    temp.time = peak_32;
		    temp.freq = peak_32 >> 16;
		    constellation.push_back(temp);
		    /* MUST incremet by this amount here*/
		    i += sizeof(peak_32);
	     }


	     delete[] memblock;
	}

	return constellation;

}

void write_constellation(std::list<peak> pruned, std::string filename){
	
	std::ofstream fout;
	uint32_t peak_32;
	struct peak temp;

	fout.open(filename+"peak", std::ios::binary | std::ios::out);
	for(std::list<peak>::iterator it = pruned.begin(); 
			it != pruned.end(); it++){

		temp = *it;
	
		peak_32 = temp.freq;
		peak_32 = peak_32 << 16;
		peak_32 |= temp.time;
		
		fout.write((char *)&peak_32,sizeof(peak_32));
	}
	
	fout.close();
}


