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

#define NFFT 256
#define BIN0 0
#define BIN1 1
#define BIN2 4
#define BIN3 13
#define BIN4 24
#define BIN5 37
#define BIN6 116

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
};

struct hash_pair {
	uint64_t fingerprint;
	struct song_data value;
};

struct count_ID {
	int count;
	int num_hashes;
};

struct database_info{
	std::string song_name;
	int hash_count;
};

std::vector<std::vector<float>> read_fft(std::string filename);

std::list<hash_pair> hash_create(std::string song_name);

std::vector<std::vector<float>> read_fft_noise(std::string filename);

std::list<hash_pair> hash_create_noise(std::string song_name);

std::list<peak> max_bins(std::vector<std::vector<float>> fft, int nfft);

std::list<peak_raw> get_peak_max_bin(std::vector<std::vector<float>> fft, 
	int fft_res, int start, int end);

std::list<peak> prune(std::list<peak_raw> peaks, int max_time);

std::list<hash_pair> generate_fingerprints(std::list<peak> pruned, 
	std::string song_name);

std::unordered_map<std::string, count_ID> identify_sample(
	std::list<hash_pair> sample_prints, 
	std::unordered_multimap<uint64_t, song_data> database,
	std::list<database_info> song_list);

int main()
{
	/*
	 * Assumes fft spectrogram files 
	 * are availible at ./song_name. 
	 */
	
	std::unordered_multimap<uint64_t, song_data> db;
	std::list<database_info> song_names;
	std::unordered_map<std::string, count_ID> results;
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
	
	int num_db = 0;	
	
	file.open("song_list.txt");
	while(getline(file, line)){
	   if(!line.empty()){

		num_db++;
		   
		temp_s = line;
		hash_count = 0;
			
		std::list<hash_pair> temp;
		temp = hash_create(temp_s);
		
		for(std::list<hash_pair>::iterator it = temp.begin(); 
			  it != temp.end(); ++it){	

			temp_db.first = it->fingerprint;
		       	temp_db.second = it->value;
			db.insert(temp_db);
			
			hash_count++;	
		}	
		
		temp_db_info.song_name = temp_s;
		temp_db_info.hash_count = hash_count;
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
		identify = hash_create_noise(temp_s + "_NOISY");
		
		std::cout << temp_s << + "_NOISY" << std::endl;

		results = identify_sample(identify, db, song_names);

		temp_match = "";	
		max_count = 0;
		for(std::list<database_info>::iterator iter = song_names.begin(); 
			iter != song_names.end(); ++iter){	
	
		float count_percent;
		count_percent = (float) results[iter->song_name].count;
		count_percent = count_percent/results[iter->song_name].num_hashes;	
				
		std::cout << "-" << iter->song_name << 
			" /" << count_percent << "/" << std::endl;
		
		if(count_percent > max_count){
			temp_match = iter->song_name;
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


std::unordered_map<std::string, count_ID> identify_sample(
	std::list<hash_pair> sample_prints, 
	std::unordered_multimap<uint64_t, song_data> database,
	std::list<database_info> song_list)
{
	std::cout << "call to identify" << std::endl;
	std::unordered_map<std::string, count_ID> results;
	for(std::list<database_info>::iterator iter = song_list.begin(); 
		iter != song_list.end(); ++iter){	
		
		results[iter->song_name].num_hashes = iter->hash_count;
		results[iter->song_name].count = 0;

	}	

	//for fingerpint in sampleFingerprints
	for(std::list<hash_pair>::iterator iter = sample_prints.begin(); 
		iter != sample_prints.end(); ++iter){	
		
	    std::pair<std::unordered_multimap<uint64_t,song_data>::iterator,
	    	std::unordered_multimap<uint64_t,song_data>::iterator> ret;
	    
	    ret = database.equal_range(iter->fingerprint);

	    for(std::unordered_multimap<uint64_t,song_data>::iterator
			    it = ret.first; it != ret.second; ++it){
		
		results[it->second.song_name].count++;
	    }    
		
	}
	return results;

}

std::list<hash_pair> hash_create(std::string song_name)
{	
	std::cout << "call to hash_create" << std::endl;
	std::vector<std::vector<float>> fft;
	fft = read_fft(song_name);	

	std::list<peak> pruned_peaks;
	pruned_peaks = max_bins(fft, NFFT);

	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name);

	return hash_entries;
}

std::list<hash_pair> hash_create_noise(std::string song_name)
{	
	std::cout << "call to hash_create_noise" << std::endl;
	std::vector<std::vector<float>> fft;
	fft = read_fft_noise(song_name);	

	std::cout << fft[0].size() << " " << fft.size() << std::endl;	
	std::list<peak> pruned_peaks;
	pruned_peaks = max_bins(fft, NFFT);

	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name);

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
			if(it->ampl <= .25*avg)
				{peaks.erase(it++);}
			else											
				{++it;}
		}	
	}  

	time = 0;
	time_bin_size = 40;
	
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
		
			if(it->ampl >= 1.75*avg)
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
	std::string song_name)
{
	std::list<hash_pair> fingerprints;
	struct fingerprint f;
	struct song_data sdata;
	struct hash_pair entry;
	uint16_t target_zone_t;
	uint64_t template_print;
	struct peak other_point;
	struct peak anchor_point;

	target_zone_t = 5;

	for(std::list<peak>::iterator it = pruned.begin(); 
		std::next(it, target_zone_t) != pruned.end(); it++){

		anchor_point= *it;
	
		for(uint16_t i = 1; i <= target_zone_t; i++){
			
			other_point = *(std::next(it,i));
			
			f.anchor = anchor_point.freq;
			f.point = other_point.freq;
			f.delta	= other_point.time - anchor_point.time;
			
			sdata.song_name = song_name;
			sdata.time_pt = anchor_point.time;
			
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
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN1, BIN2);
	temp = prune(temp_raw, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN2, BIN3);
	temp = prune(temp_raw, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN3, BIN4);
	temp = prune(temp_raw, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN4, BIN5);
	temp = prune(temp_raw, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	temp_raw = get_peak_max_bin(fft, nfft/2, BIN5, BIN6);
	temp = prune(temp_raw, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
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
		//twenty seconds if sample rate is 44.1kHz	
		} while(ss && counter < 8820);
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
