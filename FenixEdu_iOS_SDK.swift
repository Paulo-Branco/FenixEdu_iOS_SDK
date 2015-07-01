//
//  FenixEdu_iOS_SDK.swift
//  
//
//  Created by Paulo Branco on 14/06/15.
//
//

import UIKit
import Foundation

class FenixEdu_iOS_SDK: NSObject, NSURLSessionTaskDelegate {
    
    private var clientID, clientSecret, redirectURL, lang : String
    private let APIBaseURL = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1"
    private let APIRefreshTokenURL = NSURL(string: "https://fenix.tecnico.ulisboa.pt/oauth/refresh_token")
    private var backgroundURLSession : NSURLSession
    private var delegateQueue = NSOperationQueue()
    var accessToken : String?
    var accessTokenExpireDate : NSDate
    typealias APIResponseBlock = (data: NSData,httpResponse: NSHTTPURLResponse) -> ()
    private var responseHandlers : [NSURLSessionDownloadTask : APIResponseBlock] = [:]
    var refreshToken : String? {
        didSet{
            // Force a refresh of the access token whenever a new refresh token is set
            refreshAccessToken();
        }
    }
    
    // API Endpoints
    private let personEndpoint = "person"
    private let aboutEndpoint = "about"
    private let canteenEndpoint = "canteen"
    private let coursesEndpoint = "courses"
    private let evaluationsEndpoint = "evaluations"
    private let scheduleEndpoint = "schedule"
    private let groupsEndpoint = "groups"
    private let studentsEndpoint = "students"
    private let degreesEndpoint = "degrees"
    private let calendarEndpoint = "calendar"
    private let paymentsEndpoint = "payments"
    private let spacesEndpoint = "spaces"
    private let classesEndpoint = "classes"
    private let curriculumEndpoint = "curriculum"
    private let refreshTokenEndpoint = "refresh_token"
    private let carParkEndpoint = "parking"
    
    
    init(clientID :String, clientSecret :String, redirectURL :String){
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURL = redirectURL
        self.lang = "en-GB" /* Defaults to english if language is not set after init */
        self.delegateQueue = NSOperationQueue()
        self.backgroundURLSession = NSURLSession()
        self.accessTokenExpireDate = NSDate().dateByAddingTimeInterval(-9999)
        
        super.init()
        
        // Setup delegate queue properties
        self.delegateQueue.name = "FenixEdu_iOS_SDK Delegate Queue"
        self.delegateQueue.maxConcurrentOperationCount = 1
        
        // Setup the NSURLSession
        var backgroundSessionConfigurator = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("FenixEdu_iOS_SDK Background Session")
        self.backgroundURLSession = NSURLSession(configuration: backgroundSessionConfigurator, delegate: self, delegateQueue: self.delegateQueue)
        
    }
    
    func getAuthenticationURL() -> String {
        let authURL = self.APIBaseURL + "oauth/userdialog?client_id=\(self.clientID)&redirect_uri=\(self.redirectURL)"
        return authURL
    }
    
    private func setUserInfo(accessToken :String, refreshToken :String, tokenExpires :String){
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        var timeInterval : NSTimeInterval = Double(tokenExpires.toInt()!)
        self.accessTokenExpireDate = NSDate().dateByAddingTimeInterval(timeInterval)
    }
    
    
    func makeParamterStringFromDictionary(parameters :[String:String]) -> String{
        var parameterString = String()
        var parameter, key : String
        for (parameter, key) in parameters {
            if !parameterString.isEmpty {
                parameterString += "&"
            }
            parameterString += parameter + "=" + percentEscape(key)
        }
        return parameterString
    }
    
    func urlForEndpoint (endpoint: String) -> String {
        return self.APIBaseURL + "/" + endpoint
    }
    
    func makeHTTPRequest(url :NSURL, var parameters : [String:String], callbackHandler : APIResponseBlock){
        
        var urlRequest : NSMutableURLRequest = NSMutableURLRequest()
        
        // Check for an http method override. If none is found, NSURLSession defaults to GET
        if(parameters["httpMethod"] != nil){
            urlRequest.HTTPMethod = parameters["httpMethod"]!
            parameters.removeValueForKey("httpMethod")
        } else {
            urlRequest.HTTPMethod = "GET"
        }
        
        // If any parameters are still present (and this is a GET request), append them to the URL
        if(urlRequest.HTTPMethod == "GET" && !parameters.isEmpty){
            urlRequest.URL = NSURL(string: url.absoluteString! + "?" + self.makeParamterStringFromDictionary(parameters))
        } else if (!parameters.isEmpty) {
            urlRequest.URL = url
            urlRequest.HTTPBody = makeParamterStringFromDictionary(parameters).dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: true)
        }
        
        
        // Setup a new download task, and associate it with the callback handler
        var downloadTask : NSURLSessionDownloadTask = self.backgroundURLSession.downloadTaskWithRequest(urlRequest);
        self.responseHandlers[downloadTask] = callbackHandler
        downloadTask.resume()
        
    }
    
    func refreshAccessToken(){
        
        // Check if the required paramters are set
        if refreshToken == nil{
            assertionFailure("Error: Can't refresh access token without a valid refresh token")
        }
        
        // Setup the required paramters
        let requestParameters : [String: String] = ["client_id" : self.clientID,
                                                    "client_secret" : self.clientSecret,
                                                    "refresh_token" : self.refreshToken!,
                                                    "grant_type" : "refresh_token",
                                                    "httpMethod" : "POST"]
        
        
        // Setup the block that will handle the URL response
        let responseHandler : APIResponseBlock = {APIResponseBlock in
            var parseErrorHandler : NSError? = nil
            
            func failRefreshParsing() {
                println("An error occured while parsing the refresh token data. Data: \(APIResponseBlock.data) \n ResponseBlock: \(APIResponseBlock.httpResponse) \n Parse Error: \(parseErrorHandler)")
                return;
            }
            
            if let parsedData = NSJSONSerialization.JSONObjectWithData(APIResponseBlock.data, options: NSJSONReadingOptions.allZeros, error: &parseErrorHandler) as? NSDictionary {
                if let error = parseErrorHandler {
                    failRefreshParsing()
                }
                
                // Try to parse the response to grab the access token and expire period
                let accessToken = parsedData["access_token"] as? String
                let expires_in = parsedData["expires_in"] as? Int
                
                if(accessToken != nil && expires_in != nil) {
                    // Update internal variables:
                    self.accessToken = accessToken
                    self.accessTokenExpireDate = NSDate(timeInterval: Double(expires_in!), sinceDate: NSDate())
                    
                    println("Access Token: \(self.accessToken) \n Expire Date: \(self.accessTokenExpireDate)")
                }
            } else {
                failRefreshParsing()
            }
        }
        
        // Perform the Async HTTP Request
        self.makeHTTPRequest(APIRefreshTokenURL!, parameters: requestParameters, callbackHandler: responseHandler)
    }
    
    func APIPublicRequest(endpoint :String, parameters:Dictionary<String,String>, callbackHandler : (NSData, NSHTTPURLResponse) -> ()){
        
    }
    
    func APIPrivateRequest(endpoint :String, parameters:Dictionary<String,String>, callbackHandler : (NSData, NSHTTPURLResponse) -> ()){
        
        
        
        
    }
    
    
    
    // MARK: NSURLSession Delegate Protocol
    
    func URLSession(session: NSURLSession,
        task: NSURLSessionTask,
        didCompleteWithError error: NSError?){
        println("Did end task with error \(error)")
            
    }
    
    func URLSession( session: NSURLSession,
         downloadTask: NSURLSessionDownloadTask,
        didFinishDownloadingToURL location: NSURL){
         println("Calling response handler...")
        let reqData = NSData(contentsOfURL: location)
        let reqHttpResponse = downloadTask.response as! NSHTTPURLResponse
        let APIResponseBlock = self.responseHandlers[downloadTask]!
        APIResponseBlock(data: reqData!, httpResponse: reqHttpResponse)
    }
}






    // MARK: Helper Methods
    func percentEscape(str : String) -> String {
        var escapedString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, str, " ", ":/?@!$&'()*+,;=",kCFStringEncodingASCII)
        var nsTypeString = escapedString as NSString
        var swiftString:String = nsTypeString as String
        return swiftString.stringByReplacingOccurrencesOfString(" ", withString: "+", options: NSStringCompareOptions.LiteralSearch)
    }
