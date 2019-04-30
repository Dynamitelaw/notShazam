/*
 * Tomin Perea-Chamblee
 * Present Assumptions: 
 * 	1. Will be handed complete FFT Spectrogram (Python)
 *	2. Bin cutoffs are predefined
 */

#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <list>
#include <set>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cfloat>
#include <cmath>

#define NFFT 256
#define NBINS 6
#define BIN0 0
#define BIN1 1
#define BIN2 4
#define BIN3 13
#define BIN4 24
#define BIN5 37
#define BIN6 116

#define PRUNING_COEF 2.3f
#define PRUNING_TIME_WINDOW 2000
#define NORM_POW 1.5f

struct peak_raw {
	float ampl;
	uint16_t freq;
	uint16_t time;
};

struct peak {
	uint16_t freq;
	uint16_t time;
	// peak(uint16_t freq, uint16_t time) : freq(freq), time(time) {}
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
	std::list<hash_pair> sample_prints, 
	std::unordered_multimap<uint64_t, song_data> database,
	std::list<database_info> song_list);

std::list<peak> generate_constellation_map(std::vector<std::vector<float>> fft, int nfft);

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
	float max_count;
	int hash_count;
	
	std::fstream file;
	std::string line;
	std::vector<std::string> song_file_list;
	
	uint16_t num_db = 0;	
	
	file.open("song_list.txt");
	while(getline(file, line)){
	   if(!line.empty()){

		num_db++;
		   
		temp_s = line;
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

	std::cout << "Next is identifying: \n\n" << std::endl;
	
	file.open("song_list.txt");
	int correct = 0;
	num_db = 0;	 
	while(getline(file, line))
	{
		num_db++;
		std::cout << "{" <<  num_db << "} ";
		temp_s = line; 
		std::list<hash_pair> identify;
		identify = hash_create_noise(temp_s + "_NOISY", num_db);
		
		std::cout << temp_s << + "_NOISY" << std::endl;

		results = identify_sample(identify, db, song_names);

		temp_match = "";	
		max_count = 0;
		for(std::list<database_info>::iterator iter = song_names.begin(); 
			iter != song_names.end(); ++iter){	
	
		float count_percent;
		count_percent = (float) results[iter->song_ID].count;
		count_percent = count_percent/std::pow(results[iter->song_ID].num_hashes, NORM_POW);	
				
		std::cout << "-" << results[iter->song_ID].song << 
			" /" << count_percent << "/" << results[iter->song_ID].count << std::endl;
		
		if(count_percent > max_count){
			temp_match = results[iter->song_ID].song;
			max_count = count_percent;
			}
		
		}

		if(temp_match == temp_s)
		{
			correct++;
		}

		output = "Song Name: " + temp_match;
		std::cout << "*************************************"
			<< "*************************" << std::endl;
		std::cout << output << std::endl;
		std::cout << "Correctly matched: " << correct << "/" << num_db
			<< std::endl;
		std::cout << "*************************************"
			<< "*************************" << std::endl;

	}
	file.close();
	
	return 0;
}


std::unordered_map<uint16_t, count_ID> identify_sample(
	std::list<hash_pair> sample_prints, 
	std::unordered_multimap<uint64_t, song_data> database,
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
		
	    std::pair<std::unordered_multimap<uint64_t,song_data>::iterator,
	    	std::unordered_multimap<uint64_t,song_data>::iterator> ret;
	    
	    // get all the entries at this hash location
	    ret = database.equal_range(iter->fingerprint);

	    //lets insert the song_ID, time anchor pairs in our new database
	    for(std::unordered_multimap<uint64_t,song_data>::iterator
			    it = ret.first; it != ret.second; ++it){
		  
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
		if(it->second >= 4)
		{
			//std::cout << it->second << std::endl;
			identity = it->first >> 32;
			results[identity].count += (int) it->second;
		}
	}    

	return results;

}

std::list<hash_pair> hash_create(std::string song_name, uint16_t song_ID)
{	
	std::cout << "call to hash_create" << std::endl;
	std::cout << "Song ID = " << song_ID << std::endl; 
	std::vector<std::vector<float>> fft;
	fft = read_fft(song_name);	

	std::list<peak> pruned_peaks;
	pruned_peaks = generate_constellation_map(fft, NFFT);

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

	target_zone_t = 4;

	for(std::list<peak>::iterator it = pruned.begin(); 
			std::next(it, target_zone_t +3) != pruned.end(); it++){

		anchor_point= *it;
	
		for(uint16_t i = 1; i <= target_zone_t; i++){
			
			other_point = *(std::next(it, i + 3));
			
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

std::vector<std::vector<float>> read_fft_noise(std::string filename)
{
	std::cout << "call to read_fft_noise" << std::endl;
	std::fstream file;
	std::string line;
	std::vector<std::vector<float>> fft;
	file.open(filename.c_str());
	 
	while(getline(file, line)){
	   if(!line.empty()){
		std::istringstream ss(line);
		std::vector<float> line_vector;
		int counter = 0;
		do{
		  std::string word;
		  std::string::size_type sz;
		  float temp;

		  ss >> word;
		  if(!word.empty()){
		  	temp = std::stof(word, &sz);
		  }
		
		  line_vector.push_back(temp);
		  counter++;
		
		} while(ss && counter < 22050);
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
	 
	while(getline(file, line)){
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
	int avg, den;
	float num = 0;
	den = 0;
	std::list<peak> pruned_peaks;
	auto add_iter = unpruned_peaks.cbegin();
	for(auto avg_iter = unpruned_peaks.cbegin(); add_iter != unpruned_peaks.cend(); ){
		if (avg_iter->time <= time + PRUNING_TIME_WINDOW && avg_iter != unpruned_peaks.cend()) {
			den++;
			num += avg_iter->ampl;
			avg_iter++;
		} else {
			avg = num/den;
			while (add_iter != avg_iter) {
				if (add_iter->ampl > PRUNING_COEF*avg) {
					pruned_peaks.push_back({add_iter->freq, add_iter->time});
				}
				add_iter++;
			}
			num = 0;
			den = 0;
			time += PRUNING_TIME_WINDOW;
		}
	}
	return pruned_peaks;
}
				


std::list<peak> generate_constellation_map(std::vector<std::vector<float>> fft, int nfft)
{
	std::list<peak_raw> unpruned_map;
	unpruned_map = get_raw_peaks(fft, nfft);
	return prune_in_time(unpruned_map);
}

