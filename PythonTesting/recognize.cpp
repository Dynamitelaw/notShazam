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
#include <vector>
#include <unordered_map>
#include <algorithm>

// Why not 256?
#define NFFT 128
#define BIN0 0
#define BIN1 1
#define BIN2 4
#define BIN3 13
#define BIN4 24
#define BIN5 37
#define BIN6 116

struct peak_raw {
	uint8_t ampl;
	uint8_t freq;
	uint8_t time;
};

struct peak {
	uint8_t freq;
	uint8_t time;
};

struct fingerprint {
	uint8_t anchor;
	uint8_t point;
	uint8_t delta;
};

struct song_data {
	std::string song_name;
	uint8_t time_pt;
};

struct hash_pair {
	//struct fingerprint key;
	std::string fingerprint;
	struct song_data value;
};

struct count_ID {
	std::string match;
	int count;
};

std::vector<std::vector<uint8_t>> read_fft(std::string filename);

std::list<hash_pair> hash_create(std::string song_name);

std::list<peak> max_bins(
	std::vector<std::vector<uint8_t>> fft, int nfft);

std::list<peak_raw> get_peak_max_bin(
	std::vector<std::vector<uint8_t>> fft, 
	int nfft, int start, int end);

std::list<peak> prune(std::list<peak_raw> peaks, int nfft, int max_time);

std::list<hash_pair> generate_fingerprints(std::list<peak> pruned, 
	std::string song_name);

std::list<count_ID> identify_sample(std::list<hash_pair> sample_prints, 
	std::unordered_multimap<std::string, song_data> database,
	std::list<std::string> song_list);

int main()
{

	/*
	 * Assumes fft spectrogram files 
	 * are availible at ./song_name. 
	 *
	 */
	std::unordered_multimap<std::string, song_data> db;
	std::list<std::string> song_names;
	std::list<hash_pair> temp;
	std::list<hash_pair> identify;
	std::list<count_ID> results;
	std::pair <std::string, song_data> temp_db;
	struct hash_pair pair;
	std::string temp_match;
	std::string temp_s;
	std::string output;
	uint8_t max_count;

	temp_s = "City Streets_by Harren"; 
	song_names.push_back(temp_s);
	temp = hash_create(temp_s);
	for(std::list<hash_pair>::iterator it = temp.begin(); 
			  it != temp.end(); ++it){	
		temp_db.first = (*it).fingerprint;
		temp_db.second = (*it).value;
		db.insert(temp_db);
	}	

	temp_s ="Marble Machine_by Wintergatan"; 
	song_names.push_back(temp_s);
	temp = hash_create(temp_s);
	for(std::list<hash_pair>::iterator it = temp.begin(); 
			  it != temp.end(); ++it){	
		temp_db.first = (*it).fingerprint;
		temp_db.second = (*it).value;
		db.insert(temp_db);
	}	

	temp_s = "Never Gonna Give You Up_by Rick Astley"; 
	song_names.push_back(temp_s);
	temp = hash_create(temp_s);
	for(std::list<hash_pair>::iterator it = temp.begin(); 
			  it != temp.end(); ++it){	
		temp_db.first = (*it).fingerprint;
		temp_db.second = (*it).value;
		db.insert(temp_db);
	}	
	
	temp_s = "Vivir Mi Vida_by Marc Anthony";
	song_names.push_back(temp_s);
	temp = hash_create(temp_s);
	for(std::list<hash_pair>::iterator it = temp.begin(); 
			  it != temp.end(); ++it){	
		temp_db.first = (*it).fingerprint;
		temp_db.second = (*it).value;
		db.insert(temp_db);
	}	

	/*DEBUG*/
	std::cout << "Full database completed \n" << std::endl;
	std::cout << "Next is identifying: \n" << std::endl;
	
	identify = hash_create("City Streets_by Harren_NOISY");

	/*DEBUG*/
	std::cout << "Noisy fingerprints generated" << std::endl;
	
	results = identify_sample(identify, db, song_names);

	/*DEBUG*/
	std::cout << "Identify sample completed" << std::endl;

	max_count = 0;
	for(std::list<count_ID>::iterator iter = results.begin(); 
		iter != results.end(); ++iter){	
	
		std::cout << (*iter).match << " |"  
		<< (*iter).count << "| " << std::endl;
		
		if((*iter).count > max_count){
			temp_match = (*iter).match;
			max_count = (*iter).count;
		}
	}	

	output = "Song Name: " + temp_match;
	
	/*DEBUG*/
	std::cout << output << std::endl;


	return 0;
}

std::list<count_ID> identify_sample(std::list<hash_pair> sample_prints, 
	std::unordered_multimap<std::string, song_data> database,
	std::list<std::string> song_list)
{
	std::list<count_ID> results;
	for(std::list<std::string>::iterator iter = song_list.begin(); 
		iter != song_list.end(); ++iter){	
		struct count_ID new_count;
		new_count.count = 0;
		new_count.match = (*iter);
		results.push_back(new_count);
	}	

	//for fingerpint in sampleFingerprints
	for(std::list<hash_pair>::iterator iter = sample_prints.begin(); 
		iter != sample_prints.end(); ++iter){	

	    std::pair <std::unordered_multimap<std::string,song_data>::iterator, 
		    std::unordered_multimap<std::string,song_data>::iterator> ret;
	    ret = database.equal_range((*iter).fingerprint);

	    //for fingerprint[0] in hashTable
	    for (std::unordered_multimap<std::string,song_data>::iterator 
			    it=ret.first; it!=ret.second; ++it){
		    
		std::string song;
		song = (*it).second.song_name;
		for(std::list<count_ID>::iterator i = results.begin(); 
			i != results.end(); ++i){	
		
			if((*i).match == song.c_str()){
				(*i).count = (*i).count + 1;
			}
		}	
	    }    
		
	}
	return results;

}


std::vector<std::vector<uint8_t>> read_fft(std::string filename)
{
	std::fstream file;
	std::string line;
	std::vector<std::vector<uint8_t>> fft;
	file.open(filename.c_str());
	 
	while(getline(file, line)){
		std::istringstream ss(line);
		std::vector<uint8_t> line_vector;
		do{
		  std::string word;
		  int temp;
		  uint8_t utemp;

		  ss >> word;
		  temp = atoi(word.c_str());
		  utemp = (uint8_t) temp;

		  line_vector.push_back(utemp);
		} while(ss);
		fft.push_back(line_vector);
	}
	file.close();
	
	return fft;
}

std::list<hash_pair> hash_create(std::string song_name)
{	
	/*READ IN FILE*/
	std::vector<std::vector<uint8_t>> fft;
	fft = read_fft(song_name);	

	/*DEBUG*/
	std::cout << "(1) File read completed" << std::endl;
	std::cout << fft.size() << " " << fft[0].size() << std::endl;
		
	/*ROUTINE TO GENERATE PRUNED PEAKS*/
	std::list<peak> pruned_peaks;
	pruned_peaks = max_bins(fft, NFFT);

	/*DEBUG*/
	std::cout << "(2) Full list of pruned peaks completed" << std::endl;
	std::cout << pruned_peaks.size() << std::endl;

	/*ROUTINE TO GENERATE FINGERPRINTS*/
	std::list<hash_pair> hash_entries;
	hash_entries = generate_fingerprints(pruned_peaks, song_name);

	/*DEBUG*/
	std::cout << "(3) One songs worth of hashes, ready for database" 
		<< std::endl;
	std::cout << hash_entries.size() << "\n" << std::endl;

	return hash_entries;
}

/* Gets complete set of raw peaks */
std::list<peak> max_bins(
	std::vector<std::vector<uint8_t>> fft, int nfft)
{
	std::list<peak> peaks;
	std::list<peak_raw> temp_raw;
	std::list<peak> temp;

	temp_raw = get_peak_max_bin(fft, nfft, BIN0, BIN1);
	temp = prune(temp_raw, nfft, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	/*DEBUG*/
	std::cout << "--First bin, pruned" << std::endl;	
	
	temp_raw = get_peak_max_bin(fft, nfft, BIN1, BIN2);
	temp = prune(temp_raw, nfft, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	/*DEBUG*/
	std::cout << "--Second bin, pruned" << std::endl;
	
	temp_raw = get_peak_max_bin(fft, nfft, BIN2, BIN3);
	temp = prune(temp_raw, nfft, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	/*DEBUG*/
	std::cout << "--Third bin, pruned" << std::endl;
	
	temp_raw = get_peak_max_bin(fft, nfft, BIN3, BIN4);
	temp = prune(temp_raw, nfft, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	/*DEBUG*/
	std::cout << "--Fourth bin, pruned" << std::endl;
	
	temp_raw = get_peak_max_bin(fft, nfft, BIN4, BIN5);
	temp = prune(temp_raw, nfft, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	/*DEBUG*/
	std::cout << "--Fifth bin, pruned" << std::endl;
	
	temp_raw = get_peak_max_bin(fft, nfft, BIN5, BIN6);
	temp = prune(temp_raw, nfft, fft[0].size());
	while(!temp.empty()){
		peaks.push_back(temp.back());
		temp.pop_back();
	}
	
	/*DEBUG*/
	std::cout << "--Sixth bin, pruned" << std::endl;

	return peaks;
}

/* get peak max bins, returns for one bin */
std::list<peak_raw> get_peak_max_bin(
	std::vector<std::vector<uint8_t>> fft, 
	int nfft, int start, int end)
{
	std::list<peak_raw> peaks;
	uint8_t columns;
	int sample;

	columns = fft[0].size();
	sample = 1;
	// first bin
	if(!start && end){
	   for(uint8_t j = 1; j < columns-2; j++){
		if(fft[0][j] > fft[0][j-1] && //west
			fft[0][j] > fft[0][j+1] && //east
			fft[0][j] > fft[1][j]){ //south
		
		  struct peak_raw current;
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
	 for(uint8_t i = start; i < end - 2; i++){
	   for(uint8_t j = 1; j < columns-2; j++){
		if(fft[i][j] > fft[i][j-1] && //west
			fft[i][j] > fft[i][j+1] && //east
			fft[i][j] > fft[i-1][j] && //north
			fft[i][j] > fft[i+1][j]){ //south
		
		  struct peak_raw current;
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
std::list<peak> prune(std::list<peak_raw> peaks, int nfft, int max_time)
{
	int num_samples;
	int time;
	int num;
	int den;
	std::list<peak> pruned;

	time = 0;
	num_samples = 50;
	while(time < max_time)
	{
	  num = 0;
	  den = 0;
	  std::list<peak_raw> current;
	  
	  for(std::list<peak_raw>::iterator it = peaks.begin(); 
			  it != peaks.end(); ++it){
		  if((*it).time > time && 
			(*it).time < time + num_samples){
			current.push_back((*it));
			num += (*it).ampl;
			den++;
		  }
	  }	
	  
	  if(den){
	  	for(std::list<peak_raw>::iterator it = current.begin(); 
				it != current.end(); ++it){
			 if((*it).ampl > (num/den)){
				struct peak new_peak;
				new_peak.freq = (*it).freq;
				new_peak.time = (*it).time;
				pruned.push_back(new_peak);
			 }
		}	
	  }  
	  
	  time += num_samples;
	}
	return pruned;
}

std::list<hash_pair> generate_fingerprints(std::list<peak> pruned, 
	std::string song_name)
{
	uint8_t target_zone_t = 5;
	std::list<hash_pair> fingerprints;

	//probably should check that the list is at least five elements
	for(std::list<peak>::iterator 
		it = pruned.begin(); it != pruned.end(); ++it){
		
		struct peak anchor_point = *it;
		for(uint8_t i = 1; i <= target_zone_t; i++)
		{
			
			struct peak other_point = *(std::next(it,i));
			struct fingerprint f;
			f.anchor = anchor_point.freq;
			f.point = other_point.freq;
			f.delta	= other_point.time - anchor_point.time;
			struct song_data sdata;
			sdata.song_name = song_name;
			sdata.time_pt = anchor_point.time;
			struct hash_pair entry;
			entry.fingerprint = std::to_string(f.anchor) +
				std::to_string(f.point) +
				std::to_string(f.delta);
			//entry.key = f.anchor f.point d.delta;
			entry.value = sdata;
			fingerprints.push_back(entry);
		}

		if(std::next(it, 5) == pruned.end())
			break;
	}	

	return fingerprints;
}
