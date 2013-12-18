/*
 * yum -y install xmlrpc-c-devel
 * gcc -g -O0 -Wall logguestconsoles.c -o logguestconsoles -lssl $(xmlrpc-c-config client --libs) \
 *   -lcurl `pkg-config libvirt --libs` `xml2-config --cflags` `xml2-config --libs`
 *
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <ctype.h>
#include <fcntl.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <signal.h>
#include <libgen.h>
#include <regex.h>
#include <sys/inotify.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <openssl/evp.h>
#include <xmlrpc-c/base.h>
#include <xmlrpc-c/client.h>
#include <curl/curl.h>
#include <libxml/parser.h>
#include <libxml/xmlmemory.h>
#include <libxml/tree.h>

#define EVENT_SIZE ((sizeof(struct inotify_event)+FILENAME_MAX)*512)
#define BUF_SIZE 4096
#define PANIC_REGEX "(Kernel panic|Oops|general protection fault|general protection handler: wrong gs|\\(XEN\\) Panic)"
#define STDOUT_REDIRECT "/var/log/logguestconsoles.out"
#define STDERR_REDIRECT "/var/log/logguestconsoles.err"

#define DEBUG(X,fmt,...) if (DEBUG_LEVEL >= X ) { fprintf(stderr, "DEBUG%d : %s, %d " fmt "\n", X, __FILE__, __LINE__, __VA_ARGS__ ); }
#define DEBUG0(fmt,...) DEBUG(0,fmt,__VA_ARGS__)
#define DEBUG1(fmt,...) DEBUG(1,fmt,__VA_ARGS__)
#define DEBUG2(fmt,...) DEBUG(2,fmt,__VA_ARGS__)
#define DEBUG3(fmt,...) DEBUG(3,fmt,__VA_ARGS__)
#define DEBUG4(fmt,...) DEBUG(4,fmt,__VA_ARGS__)
#define DEBUG5(fmt,...) DEBUG(5,fmt,__VA_ARGS__)
#define DEBUG6(fmt,...) DEBUG(6,fmt,__VA_ARGS__)

#define LIST_INIT(mylist, thestructptr) \
	mylist.firstel = &thestructptr; \
	mylist.lastel  = &thestructptr; 

#define LIST_ADD(mylist, thestructptr) \
	mylist.lastel->next = thestructptr; \
	mylist.lastel = thestructptr;
	
typedef struct file_record file_record;
struct file_record {
	char *infilename;
	char *outfilename;
	int in_fd; 
	int out_fd;
	int wd;
	off_t in_pos;
	off_t pos;
	off_t last_uploaded_pos;
	int recipe_id;
	int panic; /* 0 : no info, 1 : paniced , -1 : watchdog=panic */
	int panic_taskid; 
	struct file_record *next;
};
typedef struct file_record *file_record_ptr;

typedef struct file_record_lst {
	file_record_ptr firstel;
	file_record_ptr lastel;
} file_record_list;

/* function prototypes */
size_t get_recipe_http_res(char *, size_t , size_t , void *); 
int prepare_and_upload(file_record_ptr);
static void startelement(void *, const xmlChar *, const xmlChar **);
static int read_config_file(int , const char *);
static void get_task_id(file_record_ptr); 
static void abort_recipe(int);
/* end of prototypes */

/* global vars */
int DEBUG_LEVEL = 0;
file_record_list thelist;
char * url = NULL;
static const char base64table[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
int inotify_fd;
char * config_file;
regex_t regex;

/* libcurl-related stuff */
struct http_res_struct {
	char *response;
	int size;
};
typedef struct http_res_struct http_res_struct;
typedef http_res_struct *  http_res_struct_ptr;
/* end of libcurl-related vars */

///// libxml2 vars //////////
enum states {
	IN_RECIPE,     /* inside the recipe we are interested in*/
	NOT_IN_RECIPE, /* not in the recipe we are searching for */
	FOUND
} parser_state;

static xmlSAXHandler handler = {
    NULL, /* internalSubset */
    NULL, /* isStandalone */
    NULL, /* hasInternalSubset */
    NULL, /* hasExternalSubset */
    NULL, /* resolveEntity */
    NULL, /* getEntity */
    NULL, /* entityDecl */
    NULL, /* notationDecl */
    NULL, /* attributeDecl */
    NULL, /* elementDecl */
    NULL, /* unparsedEntityDecl */
    NULL, /* setDocumentLocator */
    NULL, /* startDocument */
    NULL, /* endDocument */
    startelement, /* startElement */
    NULL, /* endElement */
    NULL, /* reference */
    NULL, /* characters */
    NULL, /* ignorableWhitespace */
    NULL, /* processingInstruction */
    NULL, /* comment */
    NULL, /* xmlParserWarning */
    NULL, /* xmlParserError */
    NULL, /* xmlParserError */
    NULL, /* getParameterEntity */
    NULL, /* cdataBlock; */
    NULL, /* externalSubset; */
    1,
    NULL,
    NULL, /* startElementNs */
    NULL, /* endElementNs */
    NULL  /* xmlStructuredErrorFunc */
};

static xmlSAXHandlerPtr saxhandler = &handler;
//// end of libxml2 //////

size_t get_recipe_http_res(char *res_ptr, size_t size, size_t nb_byte, void *userdata) {

	int total_bytes;
	total_bytes = size * nb_byte;
	http_res_struct_ptr my_response = (http_res_struct_ptr) userdata;

	my_response->response = realloc(my_response->response, (my_response->size + total_bytes + 1));
	if ( my_response->response == NULL ) {
		fprintf(stderr, "problem allocating memory for my_response->response");
		return -1;
	}
	memcpy(&(my_response->response[my_response->size]), res_ptr, total_bytes);
	if ( &my_response->response[my_response->size] == NULL ) {
		fprintf(stderr, "problem with copying to my_response->response");
		return -1;
	}
	my_response->size += total_bytes;
	my_response->response[my_response->size] = '\0';
	
	DEBUG4("total bytes :%d", total_bytes);
	DEBUG4("total size: %d", my_response->size);
	return total_bytes;
}

////////////////  LIBXML2 ////////////////////////////////////////////////
/* startelement callback function for saxparser */
static void
startelement(void *user_data, const xmlChar *name, const xmlChar **atts)
{
	int i=0, recipe_id_tmp;
	int recipe_id;
	file_record_ptr tmp_structptr;

	tmp_structptr = (file_record_ptr) user_data;
	recipe_id = tmp_structptr->recipe_id;
	DEBUG3(" callback for recipe %d ", recipe_id);

	if ( parser_state == FOUND || tmp_structptr->panic == -1 ) {
		DEBUG3("%s" , "parser state is found or panic is set to -1");
		return;
	}
	if ( !strcmp((char *)name, "guestrecipe") ) {
		if (atts != NULL ) {
			for (i=0; (atts[i] != NULL); i++ ) {
				if (!strcmp((char *)atts[i],"id")) {
					i++;
					recipe_id_tmp = atoi((const char *)atts[i]);
					if ( recipe_id_tmp == recipe_id ) {
						parser_state = IN_RECIPE;
					} else {
						parser_state = NOT_IN_RECIPE;
					}
				}
			}	
		}
		return;
	}
	/* <watchdog panic="ignore"/> */
	if ( !strcmp((char *)name, "watchdog") && parser_state == IN_RECIPE ) {
		if ( atts != NULL ) {
			for (i=0; (atts[i] != NULL); i++ ) {
				if (!strcmp((char *)atts[i],"panic")) {
					i++;
					if(!strcmp((char *)atts[i],"ignore")) {
						DEBUG3("panic ignored for recipe %d", recipe_id);
						tmp_structptr->panic = -1;	
					}
				}
			}
		} 
		return;
	}

	if ( !strcmp((char *)name, "task" ) && parser_state == IN_RECIPE ) {
		if ( atts != NULL ) {
			for (i=0; (atts[i] != NULL); i++ ) {
				if (!strcmp((char *)atts[i],"id")) {
					i++;
					tmp_structptr->panic_taskid = atoi((const char *)atts[i]);
					tmp_structptr->panic = 1;
				}
				if(!strcmp((char *)atts[i],"status")) {
					i++;
					if(!strcmp((char *)atts[i],"Running")) {
						parser_state = FOUND;
					}
						   
				}
			}
		}
	}
	return;
}
/*
 * reads config file which has the original console log file name per line
 */
static int read_config_file(int inotify_fd, const char *configfile ) {
	char *infilename = NULL;
	char *outfilename = NULL;
	int in_fd, out_fd, wd, errno;
	long int recipe_id;
	off_t pos_ret, in_pos_ret;
	FILE *fp;
	ssize_t line_read;
	size_t line_len = 0;
	int file_len;
	char *line = NULL; 
	char *check_str = NULL;
	char *ch = NULL;
	char *recipe_str = NULL;
	char *endptr;
	const char *suffix = ".out";
	int i = 0;
	file_record_ptr newrecord = NULL;

	if ( configfile == NULL ) {
		fprintf(stderr, "Problem in read_config_file");
		return 1;
	}
	fp = fopen(configfile, "r");
	if (!fp) {
		perror("problem opening configfile: ");
		return 1;
	}

	while ( (line_read = getline(&line, &line_len, fp) ) != -1 ) {
		check_str = NULL;
		i = 0;
		/* ignore comments */
		if ( line[0] == '#' || isspace(line[0])) {
			continue;
		}

		ch = strchr(line, ' ');
		if(!ch) {
			fprintf(stderr, "Wrong format of config file. Filename Recipeid\n");
			fclose(fp);
			return 1;
		}
		file_len = ch - line;
		infilename = malloc( (size_t) ( file_len + 1 ) );
		memcpy(infilename, &line[0], file_len);
		infilename[file_len] = '\0';

		/* if we already watching this file, continue */
		file_record_ptr el; 
		for (el = thelist.firstel; el != NULL; el=el->next) { 
			if (strcmp(el->infilename,infilename) == 0 ) {    
				check_str = el->infilename;                
				break;
			}                                           
		}
		if ( check_str != NULL ) {
			fprintf(stderr,"%s is already being watched\n",el->infilename);
			continue;
		}

		/* got the filename to watch , now get the recipeid */
		recipe_str=(char *)malloc((size_t) (line_read - file_len));
		if(!recipe_str) {
			perror("Error mallocing recipe_str: ");
			fclose(fp);
			return 1;
		}
		while ( *ch != '\0' &&  *ch != '\n' ) {
			if ( isspace(*ch) ) {
				ch++;
				continue;
			}
			recipe_str[i++] = *ch++;
		}
		recipe_str[i] = '\0';
		errno = 0;
		recipe_id = strtol(recipe_str, &endptr, 10);
		if(errno) {
			perror("Problem converting recipeid to int");
			return 1;
		}
		if ( *endptr != '\0') {
			fprintf(stderr, "%s is not a valid number\n", recipe_str);
			return 1;
		}
		fprintf(stdout, "recipe_id is: %ld \n", recipe_id);
		free(recipe_str);
			
		/* allocate space for the output file */
		outfilename = malloc( (size_t) file_len + 5 );
		if (!outfilename) {
			perror("Error mallocing for outfilename: ");
			return 1;
		}
		memcpy(outfilename, infilename, file_len);
		strcpy(&outfilename[file_len], suffix);
		fprintf(stdout, "outfilename is: %s \n", outfilename);
		in_fd = open(infilename, O_RDONLY|O_CREAT, 0777);
		if ( in_fd == -1 ) {
			perror("open in_fd: ");
			return 1;
		}
		out_fd = open(outfilename, O_WRONLY|O_CREAT|O_SYNC , 0664);
		if ( out_fd == -1 ) {
			perror("open out_fd: ");
			return 1;
		}

		in_pos_ret = lseek(in_fd, 0, SEEK_END);
		if (in_pos_ret < 0 ) {
			fprintf(stderr, "lseek in_fd\n");
			in_pos_ret = 0;
		}
		fprintf(stdout, "in_pos_ret is: %d\n", (int)in_pos_ret);

		pos_ret = lseek(out_fd, 0, SEEK_END);
		fprintf(stdout, "pos_ret is: %d\n", (int)pos_ret);
		if (pos_ret == (off_t) -1 ) {
			fprintf(stderr, "Problem seeking outputfile\n");
			close(in_fd);
			close(out_fd);
			return 1;
		}
		/* initialize a struct */
		newrecord = (file_record_ptr) malloc(sizeof(file_record));
		if (!newrecord) {
			perror("Error mallocing for newrecord: ");
			return 1;
		}
		wd = inotify_add_watch (inotify_fd, infilename, IN_MODIFY|IN_CLOSE_WRITE|IN_CLOSE_NOWRITE);
		if ( wd < 0 ) {
			perror("Error in inotify_add_watch in __FUNC__ ");
			return 1;
		}
		fprintf(stdout, "added file %s of recipe %ld for  %s to descriptor %d \n", infilename, recipe_id, outfilename, inotify_fd);
		fprintf(stdout, "in_fd %d , outfd: %d \n", in_fd, out_fd );
		fflush(stdout);

		newrecord->infilename = strdup(infilename);
		newrecord->outfilename = outfilename;
		newrecord->in_fd = in_fd;
		newrecord->out_fd = out_fd;
		newrecord->wd = wd;
		newrecord->in_pos = in_pos_ret;
		newrecord->pos = pos_ret;
		newrecord->last_uploaded_pos = pos_ret;
		newrecord->recipe_id = recipe_id;
		newrecord->panic = 0;
		newrecord->panic_taskid = -1;
		newrecord->next = NULL;


		if (thelist.firstel == NULL ) {
			thelist.firstel = newrecord;
			thelist.lastel  = newrecord;
		} else {
			LIST_ADD(thelist, newrecord);	
		}

		check_str = NULL;
				
	}
	fclose(fp);
	return 0;
}

static void submit_panic(int task_id) {
	xmlrpc_env env;
	xmlrpc_client *clientP;
	xmlrpc_value *resultP;

	xmlrpc_env_init(&env);
	if(env.fault_occurred) {	
        	fprintf(stderr, "XML-RPC Fault in xmlrpc_env_init: %s (%d)\n",
                env.fault_string, env.fault_code);
	}
	xmlrpc_client_setup_global_const(&env);
	xmlrpc_client_create(&env, XMLRPC_CLIENT_NO_FLAGS, "xmlrpc client", "1.0", NULL, 0, &clientP);
	if(env.fault_occurred) {	
        	fprintf(stderr, "XML-RPC Fault in xmlrpc_client_create: %s (%d)\n",
                env.fault_string, env.fault_code);
	}
	/* task_result(task()['id'], 'panic', '/', 0, panic.group()) */
	xmlrpc_client_call2f(&env, clientP, url, "task_result", &resultP, "(issis)",
		(xmlrpc_int) task_id, "panic", "/", (xmlrpc_int)0, " ");
	if(env.fault_occurred) {	
        	fprintf(stderr, "XML-RPC Fault in xmlrpc_client_call2f: %s (%d)\n",
                env.fault_string, env.fault_code);
	}
	xmlrpc_env_clean(&env);
	xmlrpc_client_destroy(clientP);
	xmlrpc_client_teardown_global_const();

	return;

}

static void abort_recipe(int recipe_id) {
	CURL *curl;
	CURLcode res;
	char recipe_str[32] = { '\0' };
	char * recipe_url_str;
	int host_len;
	/* url: http://%s:8000/RPC2 */
	/* /recipes/(recipe_id)/status */
	sprintf(&recipe_str[0], "%d" , recipe_id);
	host_len = strlen(url) - 4 ;
	recipe_url_str = (char *) malloc(host_len + 15 + strlen(recipe_str) + 1 );
	recipe_url_str = strncpy(recipe_url_str, url, host_len);
	sprintf(&recipe_url_str[host_len], "recipes/%s/status", recipe_str);
	recipe_url_str[host_len+15+strlen(recipe_str)] = '\0';

	curl = curl_easy_init();
	if(curl) {

		curl_easy_setopt(curl, CURLOPT_URL, recipe_url_str);
		curl_easy_setopt(curl, CURLOPT_POST, 1);
		curl_easy_setopt(curl, CURLOPT_POSTFIELDS, "status=Aborted");
		/* Perform the request, res will get the return code */ 
		res = curl_easy_perform(curl);
		/* Check for errors */ 
		if(res != CURLE_OK) {
			fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
		} else if ( res == 400 ) {
			DEBUG0("status update for recipe %d failed ..", recipe_id);
		}
		/* always cleanup */ 
		curl_easy_cleanup(curl);
		free(recipe_url_str);
	}
}

static void get_task_id(file_record_ptr therecord) {
	CURL *curl;
	CURLcode res;
	xmlParserCtxtPtr ctxt;	
	http_res_struct response_struct; 
	char recipe_str[32] = { '\0' };
	char * recipe_url_str;
	int host_len;
	int recipe_id = therecord->recipe_id;
	response_struct.response = (char *) malloc(1);
	response_struct.size = 0;
	parser_state = NOT_IN_RECIPE;

	sprintf(&recipe_str[0], "%d" , recipe_id);
	host_len = strlen(url) - 4 ;
	recipe_url_str = (char *) malloc(host_len + 8 + strlen(recipe_str) + 2 );
	recipe_url_str = strncpy(recipe_url_str, url, host_len);
	sprintf(&recipe_url_str[host_len], "recipes/%s/", recipe_str);
	recipe_url_str[host_len+8+strlen(recipe_str)+1] = '\0';

	curl = curl_easy_init();
	if(curl) {
		curl_easy_setopt(curl, CURLOPT_URL, recipe_url_str);
		curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, get_recipe_http_res);
		curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response_struct);
		/* Perform the request, res will get the return code */ 
		res = curl_easy_perform(curl);
		/* Check for errors */ 
		if(res != CURLE_OK) {
			fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
		}
		/* always cleanup */ 
		curl_easy_cleanup(curl);
		free(recipe_url_str);
	}

	/* parse xml */
	ctxt = xmlCreatePushParserCtxt(saxhandler, (void *)therecord, NULL, 0, NULL);
	xmlParseChunk(ctxt, response_struct.response, (strlen(response_struct.response) + 1), 0);
	xmlParseChunk(ctxt, response_struct.response, 0, 1);
	xmlFreeParserCtxt(ctxt);
	free(response_struct.response);
	return;

}

int prepare_and_upload(file_record_ptr therecord) {

	/* file i/o */
	off_t start_pos, end_pos;
	char *filename;
	FILE *fp;
	off_t rc;
	char *read_buf;
	size_t read_size;
	size_t read_rc;
	int i = 0;
	/* md5 stuff */
   EVP_MD_CTX mdctx;
   const EVP_MD *md;
   unsigned char md_value[EVP_MAX_MD_SIZE];
	char md_hexdigest[EVP_MAX_MD_SIZE*2];
   unsigned int md_len;
	int j;
	/* xmlrpc */
	xmlrpc_env env;
	xmlrpc_client *clientP;
	xmlrpc_value *resultP;
	/* base64 */
	int len = 0;
	int inlen = 0;
	int padit = 0;
	int outlen = 0;
	int outsize; 
	char *outstream;

	filename  = therecord->outfilename;
	start_pos = therecord->last_uploaded_pos;
	end_pos   = therecord->pos;

   OpenSSL_add_all_digests();

   md = EVP_get_digestbyname("md5");
   if(!md) {
      printf("Unknown message digest ");
      exit(1);
   }

	read_size = (size_t) end_pos - start_pos;
	if ( read_size == 0 ) {
		return 0;
	}
	//printf("readsize: %d startpos: %d endpos: %d \n", (int)read_size, (int)start_pos, (int)end_pos);
	/* read_size + 1 for the terminating \0 for regexec() function */
	read_buf = (char *)malloc(read_size+1);
	if (!read_buf) {
		perror("Error mallocing read_buf: ");
		return 1;
	}
	memset(read_buf, '\0', read_size+1);
	fp = fopen(filename, "r");
	if(!fp) {
		perror("Error opening file in __FUNC__ :");
		return 1;
	}

	rc = fseek(fp, start_pos, SEEK_SET);
	if ( rc == (off_t) -1 ) {
		perror("Error in lseek: ");
		fclose(fp);
		return 1;
	}
	read_rc = fread( read_buf, 1, read_size, fp);
	if (read_rc < 0 && (feof(fp) > 0 ) ) {
		fprintf(stderr, "Problem with reading from %s, %d\n", filename, (int)read_rc);
		fprintf(stderr, "read_buf is now: |%s| \n", read_buf);
		fclose(fp);
		free(read_buf);
		return 1;
	}
	fclose(fp);
	DEBUG5("Read buf: %s", read_buf);

	/* get rid of ^M s */
	for(i = 0; i < read_size; i++) {
		if (read_buf[i] == 0x0d) {
			read_buf[i] = 0x20;
		}
	}

	/* see if there is a panic string in the console */
   rc = regexec(&regex, read_buf, 0, NULL, 0);
	if ( rc == 0 && therecord->panic == 0 ) {
		DEBUG4("Found panic string on recipe %d ", therecord->recipe_id);
		/* if match , submit panic result */
		get_task_id(therecord);
		/* make sure that we get panic_task_id */
		if ( therecord->panic == 1 && therecord->panic_taskid != -1 ) {
			DEBUG1("submitting panic for recipe %d taskid %d", therecord->recipe_id,therecord->panic_taskid);
			submit_panic(therecord->panic_taskid);
		}

	} 
	
	
	/* encode the read_buffer */
	outsize = (( read_size / 3 ) * 4 );
	if ( read_size%3 > 0 ) {
		outsize += 4;
	}
	/* for  terminating \0 */
	outsize++;
	outstream = (char *) malloc((size_t)outsize);
	if(!outstream) {
		perror("Allocating for outstream:\n");
		free(read_buf);
		return 1;
	}
	memset(outstream, '\0', outsize);
	while ( len < read_size ) {

		for( i = 0; i < 3; i++,inlen++) {
			if ( inlen+1 > read_size ) {
				padit++;
			}
			
			if ( i == 2 && (read_size > (len+2))) {
				outstream[outlen++] = (unsigned char) base64table[ (int)(read_buf[inlen-2] >> 2) ];
				outstream[outlen++] = (unsigned char) base64table[ (int)(((read_buf[inlen-2] & 0x03) << 4) | ((read_buf[inlen-1] & 0xf0) >> 4)) ];
				outstream[outlen++] = (unsigned char) (padit >= 2 ? '=' : base64table[ (int)(((read_buf[inlen-1] & 0x0f) << 2) | ((read_buf[inlen] & 0xc0) >> 6)) ]);
				outstream[outlen++] = (unsigned char) (padit >= 1 ? '=' : base64table[ (int)(read_buf[inlen] & 0x3f) ] );	
			} else if ( i == 2 && (read_size == len+2) ) {
				outstream[outlen++] = (unsigned char) base64table[ (int)(read_buf[inlen-2] >> 2) ];
				outstream[outlen++] = (unsigned char) base64table[ (int)(((read_buf[inlen-2] & 0x03) << 4) | ((read_buf[inlen-1] & 0xf0) >> 4)) ];
				outstream[outlen++] = (unsigned char) base64table[ (int)(((read_buf[inlen-1] & 0x0f) << 2))];
				outstream[outlen++] = '=';
			} else if ( i == 2 && (read_size == len+1) ) {
				outstream[outlen++] = (unsigned char) base64table[ (int)(read_buf[inlen-2] >> 2) ];
				outstream[outlen++] = (unsigned char) base64table[ (int)(((read_buf[inlen-2] & 0x03) << 4)) ];
				outstream[outlen++] = '=';
				outstream[outlen++] = '=';
			} 
		}
		len += 3;
	}
		
	outstream[outlen] = '\0';

	/* md5 hashsum of the blob */
   EVP_MD_CTX_init(&mdctx);
   EVP_DigestInit_ex(&mdctx, md, NULL);
   EVP_DigestUpdate(&mdctx, read_buf, read_size);
   EVP_DigestFinal_ex(&mdctx, md_value, &md_len);
   EVP_MD_CTX_cleanup(&mdctx);

   for(i = 0, j = 0; i < md_len; i++){
		sprintf(&md_hexdigest[j], "%02x", md_value[i]);
		j += 2;
   }
	md_hexdigest[j] = '\0';
	

	xmlrpc_env_init(&env);
	if(env.fault_occurred) {	
      fprintf(stderr, "XML-RPC Fault in xmlrpc_env_init: %s (%d)\n",
         env.fault_string, env.fault_code);
	}
	xmlrpc_client_setup_global_const(&env);
	xmlrpc_client_create(&env, XMLRPC_CLIENT_NO_FLAGS, "xmlrpc client", "1.0", NULL, 0, &clientP);
	if(env.fault_occurred) {	
      fprintf(stderr, "XML-RPC Fault in xmlrpc_client_create: %s (%d)\n",
         env.fault_string, env.fault_code);
	}
	xmlrpc_client_call2f(&env, clientP, url, "recipe_upload_file", &resultP, "(issisis)",
		(xmlrpc_int) therecord->recipe_id, "/", "console.log", (xmlrpc_int)read_size, 
		md_hexdigest,(xmlrpc_int)start_pos, outstream);
	if(env.fault_occurred) {	
      fprintf(stderr, "XML-RPC Fault in xmlrpc_client_call2f: %s (%d)\n",
         env.fault_string, env.fault_code);
	}
	xmlrpc_env_clean(&env);
	xmlrpc_client_destroy(clientP);
	xmlrpc_client_teardown_global_const();

	therecord->last_uploaded_pos = (end_pos - 1);
	/* if we got panic and no ignore, update the the recipe status */
	if ( therecord->panic ==  1 ) {
		DEBUG1("Aborting recipe: %d ", therecord->recipe_id);
		abort_recipe(therecord->recipe_id);
	}
	free(outstream);
	free(read_buf);
	return 0;
}

void sighandler (int sig)
{
	DEBUG0("calling sighandler for %d", sig);

	if ( sig == SIGTERM || sig == SIGINT ) {
		DEBUG0("calling sighandler for %d", sig);
		fflush(stdout);
		fflush(stderr);
	} else if ( sig == SIGUSR1 ) {
		DEBUG0("got SIGUSR1, reloading the config file %s", config_file);		
		fflush(stdout);
		fflush(stderr);
		read_config_file(inotify_fd, config_file);
	}
}

int main(int argc, char *argv[], char *envp[]) {
	int wr_ret;
	int in_fd, out_fd;
	ssize_t len = -1 , i = 0;
	char events[EVENT_SIZE] = {0};
	ssize_t read_bytes;
	char read_buf[BUF_SIZE];
	off_t in_pos, in_pos_end;
	int rc;
	int found = 0;
	char *tmp_url = NULL;
	char *pidfile = NULL;
	char *baseprogname = NULL;
	char *lc_arg = NULL;
	FILE *PIDFP;
	pid_t pid, sid, childpid;
	thelist.firstel = NULL;
	thelist.lastel = NULL;
	struct sigaction reload_action;

	memset(&reload_action, 0, sizeof(reload_action));
	reload_action.sa_handler = sighandler;



	if ( argc < 3 ) {
		fprintf(stderr, "Usage: %s [--config configfile] <--lc lab_controller>\n", argv[0]);
		return 1;
	}

	for(i = 0; i < argc; i++) {
		if ( strncmp(argv[i],"--config",8) == 0 ) {
			i++;
			config_file=strdup(argv[i]);
		} else if ( strncmp(argv[i],"--pidfile",9) == 0 ) {
			i++;
			pidfile=strdup(argv[i]);
		} else if ( strncmp(argv[i],"--lc", 4) == 0 ) {
			i++;
			lc_arg=strdup(argv[i]);
		} else if ( strncmp(argv[i],"--v",3) == 0 ) {
			int debug_len = strlen(argv[i]) - 2;
			char * tmp_str = (char *) malloc(debug_len+1);

			memset(tmp_str, 'v', debug_len); 
			tmp_str[debug_len] = '\0';
			if ( strncmp(tmp_str, &argv[i][2], debug_len) == 0 ) {
				DEBUG_LEVEL = debug_len;
				printf("Debug level : %d \n", DEBUG_LEVEL);
			}
		} 
	}
	if (!config_file) {
		fprintf(stderr, "Usage: %s [--config configfile] <--pidfile pidfile>\n", argv[0]);
		return 1;
	}
	if ( !pidfile ) {
		baseprogname = basename(argv[0]);
		i = strlen(baseprogname);
		pidfile = (char *)malloc(i+14);
		strncpy(pidfile,"/var/run/", 9);
		strncpy(&pidfile[9],baseprogname,i);
		strcpy(&pidfile[9+i],".pid");
	}

	sigaction(SIGTERM, &reload_action, NULL);
	sigaction(SIGINT,  &reload_action, NULL);
	sigaction(SIGUSR1, &reload_action, NULL);
	/* daemonize */
	pid = fork();
	if ( pid < 0 ) {
		perror("Error with forking\n");
		return 1;
	} else if ( pid > 0 ) {
		return 0;
	}

	sid = setsid();
	if ( sid < 0 ) {
		perror("problem with setsid(): \n");
		return 1;
	}

	if ( chdir("/") != 0 ) {
		perror("problem with chdir(): \n");
		return 1;
	}
	childpid = getpid();
	fprintf(stdout,"childpid : %d \n", childpid);
	PIDFP = fopen(pidfile, "w" );
	if (!PIDFP) {
		fprintf(stderr, "Can't open pidfile");
		return 1;
	}
	rc = fprintf(PIDFP, "%d\n", childpid);
	if ( rc < 0 ) {
		fprintf(stderr, "Problem with writing the pidfile");
		return 1;
	}
	fflush(PIDFP);
	
	close(STDIN_FILENO);
	freopen(STDOUT_REDIRECT, "a", stdout);
	if(!stdout) {
		perror("Error redirecting stdout: \n");
		return 1;
	}
	freopen(STDERR_REDIRECT, "a", stderr);
	if(!stderr) {
		perror("Error redirecting stderr: \n");
		return 1;
	}
	
	/* if we get lan controller given on the command line, use it , or else see if
 	 * there is LAB_CONTROLLER env. variable 
 	 */
	if ( lc_arg ) {
		url = lc_arg;
	} else {
		url = getenv("LAB_CONTROLLER");
	}

	if ( url == NULL ) {
		fprintf(stderr, "No Lab controller given on command line or env. vars\n");
		return 1;
	} 
	/* http://$LAB_CONTROLLER:8000/RPC2 */
	tmp_url = (char *) malloc(strlen(url) + 18);
	snprintf(tmp_url, (size_t) (strlen(url) + 18),  "http://%s:8000/RPC2", url);
	url = tmp_url;
	
	fprintf(stdout, "LAB CONTROLLER is : %s \n", url);
	
	/* compile regex */
	rc = regcomp(&regex, PANIC_REGEX, REG_EXTENDED);
	if ( rc ) {
		perror("Problem with compiling regex: ");
		return 1;
	}

	inotify_fd = inotify_init();
	if ( inotify_fd < 0 ) {
		perror("Error inotify_init: ");
		return 1;
	}
	rc = read_config_file(inotify_fd, config_file);
	if(rc) {
		fprintf(stderr, "Error reading config file\n");
		return 1;
	}
	while (1) {
		len = read (inotify_fd, events, EVENT_SIZE);
		for (i=0; i < len; i++) {
			struct inotify_event *event = (struct inotify_event *)&events[i];
			/* find the wd in the list */
			file_record_ptr el = NULL; 
			found = 0;
			for (el = thelist.firstel; el != NULL; el=el->next) { 
				if (el->wd == event->wd ) {    
					in_fd = el->in_fd;
					out_fd = el->out_fd;
					found = 1;
					DEBUG3("event for recipe: %d", el->recipe_id);
					break;
				}                                           
			}

			if ( found == 0 ) {
				continue;
			}

			if (event->mask & IN_MODIFY) {
				in_pos = lseek(in_fd, 0, SEEK_CUR);
				if (in_pos < 0) {
					fprintf(stderr, "IN_MODIFY lseek err\n");
				} else {
					in_pos_end = lseek(in_fd, 0, SEEK_END);
					if (in_pos_end < 0) {
						fprintf(stderr, "lseek SEEK_END err\n");
					} else {
						/* in file was truncated, seek to beginning */
						if (in_pos_end < el->in_pos)
							in_pos = 0;
					}
					lseek(in_fd, in_pos, SEEK_SET);
				}

				while( (read_bytes = read(in_fd, read_buf, BUF_SIZE) ) > 0 ) {
					wr_ret = write(out_fd,read_buf,read_bytes);
					DEBUG3("written in_fd: %d", in_fd);
					DEBUG3("written %d bytes:", wr_ret);
					if ( wr_ret == -1 ) {
						perror("Error writing out: ");
						return 1;
					}
					el->pos = lseek(out_fd, 0L, SEEK_CUR);
					if ( el->pos == (off_t) -1 ) {
						fprintf(stderr,"Problem reading pos from outfd\n");
						return 1;
					}
					if ((off_t) (el->pos - el->last_uploaded_pos) > 1024) {
						prepare_and_upload(el);
					}
				}
				in_pos_end = lseek(in_fd, 0, SEEK_CUR);
				if (in_pos_end < 0) {
					fprintf(stderr, "lseek in_fd after write err\n");
				} else {
					el->in_pos = in_pos_end;
				}
			} else if ((event->mask & IN_CLOSE_WRITE) || (event->mask & IN_CLOSE_NOWRITE) ) {
				prepare_and_upload(el);
			} 

		}
		bzero(&events[0],EVENT_SIZE);
	}
	return 0;
}

