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

/*
#define NFFT 256
#define NBINS 6
#define BIN0 0
#define BIN1 5
#define BIN2 10
#define BIN3 20
#define BIN4 40
#define BIN5 80
#define BIN6 120
*/
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

std::vector<std::vector<float>> read_fft(std::string filename);

std::list<hash_pair> hash_create(std::string song_name, uint16_t song_ID);

std::vector<std::vector<float>> read_fft_noise(std::string filename);

std::list<hash_pair> hash_create_noise(std::string song_name, uint16_t song_ID);

std::list<peak> max_bins(std::vector<std::vector<float>> fft, int nfft);

std::list<peak_raw> get_peak_max_bin(std::vector<std::vector<float>> fft, 
	int fft_res, int start, int end);

std::list<peak> prune(std::list<peak_raw> peaks, int max_time);

std::list<hash_pair> generate_fingerprints(std::list<peak> pruned, 
	std::string song_name, uint16_t song_ID);

std::unordered_map<uint16_t, count_ID> identify_sample(
	const std::list<hash_pair> & sample_prints, 
	const std::unordered_multimap<uint64_t, song_data> & database,
	std::list<database_info> song_list);

std::list<peak> generate_constellation_map(std::vector<std::vector<float>> fft, int nfft);

void write_constellation(std::list<peak> pruned, std::string filename);

std::list<peak> read_constellation(std::string filename);

std::vector<std::vector<float>> get_fft_from_audio(float sec);

std::list<hash_pair> hash_create_from_audio(float sec);

float score(const struct count_ID &c) {
	return ((float) c.count)/std::pow(c.num_hashes, NORM_POW);	
}
bool sortByScore(const struct count_ID &lhs, const struct count_ID &rhs) { 
	return score(lhs) > score(rhs); 
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
	
	file.open("song_list.txt");
	while(getline(file, line)){
	   if(!line.empty()){

		num_db++;
		   
		temp_s = "./constellationFiles/"+ line;
		hash_count = 0;
			
		std::list<hash_pair> temp;
		temp = hash_create(temp_s, num_db);
		
		for(std::list<hash_pair>::iterator it = temp.begin(); 
			  it != temp.end(); ++it){	

			temp_db.first = it->fingerprint;
		       	temp_db.second = it->value;
			db.insert(temp_db);
			
			hash_count++;	
		}	
		
		temp_db_info.song_name = temp_s;
		temp_db_info.hash_count = hash_count;
		temp_db_info.song_ID = num_db;
		song_names.push_back(temp_db_info);
	   	
		std::cout <<  "(" << num_db << ") ";
		std::cout << temp_s;
		std::cout << " databased.\n Number of hash table entries: ";
		std::cout << temp.size() << std::endl;
	     	std::cout << std::endl;
	     	std::cout << std::endl;
	   }
	}
	file.close();

	/*DEBUG*/
	std::cout << "Full database completed \n\n" << std::endl;

	
	while(true)
	{
		std::cout << "Ready to identify. Press ENTER to identify the song playing.\n";
		std::cin.ignore();

		temp_s = line; 
		std::list<hash_pair> identify;
		// identify = hash_create_noise(temp_s, num_db);
		identify = hash_create_from_audio(15);
		std::cout << "Done listening.\n"; 
		

		results = identify_sample(identify, db, song_names);

		std::vector<count_ID> sorted_results;
		for(auto iter = results.begin(); 
			iter != results.end(); ++iter){	
			sorted_results.push_back(iter->second);
		}
		std::sort(sorted_results.begin(), sorted_results.end(), sortByScore);
		for (auto c = sorted_results.cbegin(); c != sorted_results.cend(); c++) {
		    std::cout << "-" << c->song << " /" << score(*c) << "/" << c->count << std::endl;
		}

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
	//std::vector<std::vector<float>> fft;
	//fft = read_fft(song_name);	

	std::list<peak> pruned_peaks;
	//pruned_peaks = generate_constellation_map(fft, NFFT);
	pruned_peaks = read_constellation(song_name);			
	/*
	//write_constellation(pruned_peaks, song_name);
	//check that read constellation is the same
	if(song_ID)
	{
		std::list<peak> pruned_copy;
		pruned_copy = read_constellation(song_name);
		if(pruned_copy.front().freq == pruned_peaks.front().freq
			&& pruned_copy.front().time == pruned_peaks.front().time
			&& pruned_copy.back().freq == pruned_peaks.back().freq
			&& pruned_copy.back().time == pruned_peaks.back().time)
		{
			std::cout << "Proper constellation stored\n";
		}
		else
		{
			std::cout << "Error storing/reading constellation\n";
		}
	}	
	*/
	
	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name, song_ID);

	return hash_entries;
}

std::list<hash_pair> hash_create_noise(std::string song_name, uint16_t song_ID)
{	
	std::cout << "call to hash_create_noise" << std::endl;
	std::vector<std::vector<float>> fft;
	fft = read_fft_noise(song_name);	

	std::list<peak> pruned_peaks;
	pruned_peaks = generate_constellation_map(fft, NFFT);

	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name, song_ID);

	return hash_entries;
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


/* get peak max bins, returns for one bin */
std::list<peak_raw> get_peak_max_bin(
	std::vector<std::vector<float>> fft, 
	int fft_res, int start, int end)
{
	std::cout << "call to get_peak_max_bin" << std::endl;
	std::list<peak_raw> peaks;
	uint16_t columns;
	uint16_t sample;
	struct peak_raw current;

	columns = fft[0].size();
	sample = 1;
	// first bin
	// Assumes first bin has only the zero freq.
	if(!start && end){
	   for(uint16_t j = 1; j < columns-2; j++){
		if(fft[0][j] > fft[0][j-1] && //west
			fft[0][j] > fft[0][j+1] && //east
			fft[0][j] > fft[1][j]){ //south
		
		  current.freq = 0;
		  current.ampl = fft[0][j];
		  current.time = sample;
		  peaks.push_back(current);
		  sample++;
		}
	   }
	}
	// remaining bins
	else{
	 for(uint16_t i = start; i < end - 2; i++){
	   for(uint16_t j = 1; j < columns-2; j++){
		if(fft[i][j] > fft[i][j-1] && //west
			fft[i][j] > fft[i][j+1] && //east
			fft[i][j] > fft[i-1][j] && //north
			fft[i][j] > fft[i+1][j]){ //south
		
		  current.freq = i;
		  current.ampl = fft[i][j];
		  current.time = sample;
		  peaks.push_back(current);
		  sample++;
		}
	   }
	 }
	}
	return peaks;
}

/* prune a bin of peaks, returns processed std::list */
std::list<peak> prune(std::list<peak_raw> peaks, int max_time)
{
	std::cout << "call to prune" << std::endl;
	int time_bin_size;
	int time;
	float num;
	int den;
	float avg;
	std::list<peak_raw> current;
	std::list<peak> pruned;
	struct peak new_peak; 
	std::set<uint16_t> sample_set;
	std::pair<std::set<uint16_t>::iterator,bool> ret;

	num = 0;
	den = 0;
	for(std::list<peak_raw>::iterator it = peaks.begin(); 
		    it != peaks.end(); ++it){
		num += it->ampl;
		den++;
	}
				
	if(den){
		avg = num/den;
		std::list<peak_raw>::iterator it = peaks.begin(); 
		
		while(it !=peaks.end()){
			if(it->ampl <= .125*avg)
				{peaks.erase(it++);}
			else											
				{++it;}
		}	
	}  

	time = 0;
	time_bin_size = 50;
	
	while(time < max_time){

	  num = 0;
	  den = 0;
	  
	  for(std::list<peak_raw>::iterator it = peaks.begin(); 
			  it != peaks.end(); ++it){	  
		  
		  if(it->time > time && it->time < time + time_bin_size){
		
			ret = sample_set.insert(it->time);
			if(ret.second){
			  current.push_back(*it);
			  num += it->ampl;
			  den++;
			}
			else{
	  		  for(std::list<peak_raw>::iterator 
				iter = current.begin(); 
		    		iter != current.end(); ++iter){
					
				if(iter->time == it->time){
					//greater, update list
					if(it->ampl > iter->ampl){
						num -= iter->ampl;
						current.erase(iter);
			  			current.push_back(*it);
			  			num += it->ampl;
					}
					// there should only be one
					// so leave this inner loop
			   		break;		   	
				}
			  }
			}
		  }
	  }	

	  if(den){

	  	avg = num/den;
	  	for(std::list<peak_raw>::iterator it = current.begin(); 
		    it != current.end(); ++it){
		
			if(it->ampl >= 1.85*avg)
			{
				new_peak.freq =	it->freq;
				new_peak.time = it->time;
				pruned.push_back(new_peak);
			}
		}	
	  }  
	  
	  time += time_bin_size;
	  current = std::list<peak_raw>();
	}

	return pruned;
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


/* Gets complete set of processed peaks */
std::list<peak> max_bins(std::vector<std::vector<float>> fft, int nfft)
{
	std::list<peak> peaks;
	std::list<peak_raw> temp_raw;
	std::list<peak> temp;

	temp_raw = get_peak_max_bin(fft, nfft/2, BIN0, BIN1);
	temp = prune(temp_raw, fft[0].size());
	peaks.splice(peaks.end(), temp);
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN1, BIN2);
	temp = prune(temp_raw, fft[0].size());
	peaks.splice(peaks.end(), temp);
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN2, BIN3);
	temp = prune(temp_raw, fft[0].size());
	peaks.splice(peaks.end(), temp);
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN3, BIN4);
	temp = prune(temp_raw, fft[0].size());
	peaks.splice(peaks.end(), temp);
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN4, BIN5);
	temp = prune(temp_raw, fft[0].size());
	peaks.splice(peaks.end(), temp);
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN5, BIN6);
	temp = prune(temp_raw, fft[0].size());
	peaks.splice(peaks.end(), temp);
	
	return peaks;
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

	fft.reserve(N_FREQUENCIES);

	if (ioctl(fft_accelerator_fd, FFT_ACCELERATOR_READ_FFT, &vla)) {
		perror("ioctl(FFT_ACCELERATOR_READ_FFT) failed");
		return ERR_IO;
	}
	if(!fft_struct.valid) {
		return ERR_NVALID;
	}
	for (int i = 0; i < N_FREQUENCIES; i++) {
		std::cout << fft_struct.fft[i] << " ";
		fft.push_back(ampl2float(fft_struct.fft[i]));
	}
		std::cout << std::endl;
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

			spec[j].push_back(fft_temp[j]);
		}	
		//if (time == ERR_IO || time == ERR_NVALID) {
		//	std::cout << "Could not get audio fft\n";
			// spec[0].size < samples
		//	return spec;
		//}
		// copy contents of fft_temp into spec[i], averaging if there are missed times.
	}
	return spec;
}

std::vector<std::vector<float>> read_fft_noise(std::string filename)
{
	std::cout << "call to read_fft_noise" << std::endl;
	std::fstream file;
	std::string line;
	std::vector<std::vector<float>> fft;
	file.open(filename.c_str());
	bool first = true;

	int offset = 20000;
	 
	while(getline(file, line)){
	   if (first) {
               first = false;
	       continue;
	   }
	   if(!line.empty()){
		std::istringstream ss(line);
		std::vector<float> line_vector;
		int counter = 0;
		do{
		  std::string word;
		  std::string::size_type sz;
		  float temp;

		  if (counter < offset) {
			  counter++;
			  continue;
		  }

		  ss >> word;
		  if(!word.empty()){
		  	temp = std::stof(word, &sz);
		  }
		
		  line_vector.push_back(temp);
		  counter++;
		
		} while(ss && counter <  offset + 11025/2);
		fft.push_back(line_vector);
	   }
	}
	file.close();
	
	return fft;
}


std::vector<std::vector<float>> read_fft(std::string filename)
{
	std::cout << "call to read_fft" << std::endl;
	std::fstream file;
	std::string line;
	std::vector<std::vector<float>> fft;
	file.open(filename.c_str());
	bool first = true;
	 
	while(getline(file, line)){
	   if (first) {
               first = false;
	       continue;
	   }
	   if(!line.empty()){
		std::istringstream ss(line);
		std::vector<float> line_vector;
		do{
		  std::string word;
		  std::string::size_type sz;
		  float temp;

		  ss >> word;
		  if(!word.empty()){
		  	temp = std::stof(word, &sz);
		  }
		
		  line_vector.push_back(temp);
		
		} while(ss);
		fft.push_back(line_vector);
	   }
	}
	file.close();
	
	return fft;
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

void write_constellation(std::list<peak> pruned, std::string filename){
	
	std::ofstream fout;
	uint32_t peak_32;
	struct peak temp;

	fout.open(filename+".peak", std::ios::binary | std::ios::out);
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


std::list<peak> read_constellation(std::string filename){

	std::ifstream fin;
	std::list<peak> constellation;
	uint32_t peak_32;
	struct peak temp;
	std::streampos size;
  	char * memblock;
	int i;
	
	fin.open(filename+".peak", std::ios::binary | std::ios::in 
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
