//
//  FenixEdu_iOS_SDK.swift
//  
//
//  Created by Paulo Branco on 14/06/15.
//
//

import UIKit
import Foundation

/**
    A Swift iOS Wrapper to access FenixEdu's API
*/
public class FenixEdu_iOS_SDK: NSObject, NSURLSessionTaskDelegate {
    
    private var clientID, clientSecret, redirectURL, lang : String
    private let APIBaseURL = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1"
    private let APIRefreshTokenURL = NSURL(string: "https://fenix.tecnico.ulisboa.pt/oauth/refresh_token")
    private var backgroundURLSession : NSURLSession
    private var delegateQueue = NSOperationQueue()
    var accessToken : String?
    var accessTokenExpireDate : NSDate
    typealias APIResponseBlock = (data: NSData?,httpResponse: NSHTTPURLResponse?) -> ()
    private var responseHandlers : [Int : APIResponseBlock] = [:]
    public var refreshToken : String? {
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
    private let shuttleEndpoint = "shuttle"
    
    
    
    /**
    Initializes a new instance of the FenixEdu Api Wrapper class.
    Each instance has its own delegate queue and background NSURL Session.
    
    :param: clientID         Your application's Client ID
    :param: clientSecret     Your application's Client Secret
    :param: redirectURL      Your application's RedirectURL

    :returns:                 An initialized FenixEdu instance.
    */
    public init(clientID :String, clientSecret :String, redirectURL :String){
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
        let backgroundSessionConfigurator : NSURLSessionConfiguration
        if #available(iOS 8.0, *) {
            backgroundSessionConfigurator = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("FenixEdu_iOS_SDK Background Session - \(random())")
        } else {
            backgroundSessionConfigurator = NSURLSessionConfiguration.backgroundSessionConfiguration("FenixEdu_iOS_SDK Background Session - \(random())")
        }
        self.backgroundURLSession = NSURLSession(configuration: backgroundSessionConfigurator, delegate: self, delegateQueue: self.delegateQueue)
        
    }
    
    deinit{
        self.backgroundURLSession.invalidateAndCancel()
        self.delegateQueue.cancelAllOperations()
    }
    
    private func makeParamterStringFromDictionary(parameters :[String:String]) -> String{
        var parameterString = String()
        for (parameter, key) in parameters {
            if !parameterString.isEmpty {
                parameterString += "&"
            }
            parameterString += parameter + "=" + percentEscape(key)
        }
        return parameterString
    }
    
    private func urlForEndpoint (endpoint: String) -> String {
        return self.APIBaseURL + "/" + endpoint
    }
    
    private func makeHTTPRequest(url :NSURL, var parameters : [String:String], callbackHandler : APIResponseBlock){
        
        let urlRequest : NSMutableURLRequest = NSMutableURLRequest()
        
        // Check for an http method override. If none is found, NSURLSession defaults to GET
        if(parameters["httpMethod"] != nil){
            urlRequest.HTTPMethod = parameters["httpMethod"]!
            parameters.removeValueForKey("httpMethod")
        } else {
            urlRequest.HTTPMethod = "GET"
        }
        
        // If any parameters are still present (and this is a GET request), append them to the URL
        if(urlRequest.HTTPMethod == "GET" && !parameters.isEmpty){
            urlRequest.URL = NSURL(string: url.absoluteString +  "?" + self.makeParamterStringFromDictionary(parameters))
        } else if (!parameters.isEmpty) {
            urlRequest.URL = url
            urlRequest.HTTPBody = makeParamterStringFromDictionary(parameters).dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: true)
        }
        
        
        // Setup a new download task, and associate it with the callback handler
        let downloadTask : NSURLSessionDownloadTask = self.backgroundURLSession.downloadTaskWithRequest(urlRequest)!;
        self.responseHandlers[downloadTask.taskIdentifier] = callbackHandler
        downloadTask.resume()
        
    }

    
    private func APIPublicRequest(endpoint :String, parameters:[String:String]?, callbackHandler : APIResponseBlock){
        
        // Inject the lang parameter in the parameter list
        var requestParameters = parameters ?? [:]
        requestParameters["lang"] = self.lang
        
        // Setup the URL Request with the URL Encoded parameters
        self.makeHTTPRequest(NSURL(string: urlForEndpoint(endpoint))!, parameters: requestParameters, callbackHandler: callbackHandler)
    }
    
    private func APIPrivateRequest(endpoint :String, parameters:[String:String]?, callbackHandler : APIResponseBlock){
        
        // Inject the lang parameter
        var requestParameters = parameters ?? [:]
        requestParameters["lang"] = self.lang
        
        // Override the HTTP Method if the endpoint has a custom hhtp method
        /*  Note: As of the latest revision, the only endpoint that doesn't use a GET http method is evaluation/{id}⁄enrol.
        *   This will be revised once other write endpoints are created.
        */
        if endpoint.rangeOfString("enrol") != nil {
            requestParameters["httpMethod"] = "PUT"
        }
        
        // Check the current access token status:
        guard let _ = accessToken else {
            // Refresh the access token before continuing
            let refreshTokenHandler = { () -> () in
                requestParameters["access_token"] = self.accessToken
                self.makeHTTPRequest(NSURL(string: self.urlForEndpoint(endpoint))!, parameters: requestParameters, callbackHandler: callbackHandler)
            }
            self.refreshAccessToken(refreshTokenHandler)
            return;
        }
        // If the access token is valid, start the http request
        requestParameters["access_token"] = self.accessToken
        self.makeHTTPRequest(NSURL(string: urlForEndpoint(endpoint))!, parameters: requestParameters, callbackHandler: callbackHandler)
        
        
    }
    
    
    // MARK: Public Authentication Methods
    
    /**
    Returns the authentication URL for the CAS login page.
    
    :returns:                 The CAS authentication login URL.
    */
    public func getAuthenticationURL() -> NSURL {
        return NSURL(string: self.APIBaseURL + "oauth/userdialog?client_id=\(self.clientID)&redirect_uri=\(self.redirectURL)")!
    }
    
    
    /**
    Forces a refresh of the access token. This will fail if there isn't a refresh token set.
    Also, please note that a new access token will be automatically requested whenever the refresh token is changed.
    */
    public func refreshAccessToken(optionalHandler : (()->())? = nil){
        
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
                print("An error occured while parsing the refresh token data. Data: \(APIResponseBlock.data) \n ResponseBlock: \(APIResponseBlock.httpResponse) \n Parse Error: \(parseErrorHandler)")
                //return;
            }
            
            // Check if the refresh token is valid
            if APIResponseBlock.httpResponse!.statusCode == 401 {
                print("Error: The provided refresh token is no longer valid. Access Token refresh failed.")
                return;
            }
            
            // FIXME: Missing clientID / clientSecret revocation check
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(APIResponseBlock.data!, options: NSJSONReadingOptions.MutableLeaves) as! NSDictionary
                // Try to parse the response to grab the access token and expire period
                
                guard let accessToken = parsedData["access_token"], let expires_in = parsedData["expires_in"] else {
                    failRefreshParsing()
                    return;
                }
                
                // Update internal variables:
                self.accessToken = accessToken as? String
                self.accessTokenExpireDate = NSDate(timeInterval: Double(expires_in as! NSNumber), sinceDate: NSDate())
                
                if optionalHandler != nil{
                    optionalHandler!()
                }
                
            } catch {
                failRefreshParsing()
            }
        }
        
        // Perform the Async HTTP Request
        self.makeHTTPRequest(APIRefreshTokenURL!, parameters: requestParameters, callbackHandler: responseHandler)
    }
    
    
    /**
    Opens the application authorization prompt in the systemms's default browser
    */
    public func startExternalAuthentication(){
        UIApplication.sharedApplication().openURL(NSURL(string: "https://fenix.tecnico.ulisboa.pt/oauth/userdialog?client_id=\(self.clientID)&redirect_uri=\(self.redirectURL)")!)
    }
    
    
    // MARK: Public Endpoints
    
    
    /** Returns some basic information about the institution where the application is deployed. It also returns a list of RSS feeds, the current academic term, available languages and default language. An example response can be found in http://fenixedu.org/dev/api/#toc_4
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an Optional NSDictionary with the parsed JSON data, or nil if an error occurs.
    */
    public func getAbout(completionBlock: (aboutData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(aboutData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(aboutData: parsedData)
            } catch {
                completionBlock(aboutData: nil)
            }
        }
        
        APIPublicRequest(aboutEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** Returns information about the menus served at the main canteen of the institution where the application is deployed. The information is provided in the supported languages (currently Portuguese and English). An example response can be found in http://fenixedu.org/dev/api/#toc_10
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an Optional NSArray with the parsed JSON data, or nil if an error occurs.
    */
    public func getCanteen(completionBlock: (canteenData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(canteenData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(canteenData: parsedData)
            } catch {
                completionBlock(canteenData: nil)
            }
        }
        
        APIPublicRequest(canteenEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    
    /** A course is a concrete unit of teaching that typically lasts one academic term. This class method returns some information regarding a particular course. Courses are identified with a numeric code that you need to provide. An example response can be found in http://fenixedu.org/dev/api/#toc_10
    
    :param: courseID                The ID number of the course you wish to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an Optional NSDictionary with the parsed JSON data, or nil if an error occurs.
    */
    public func getCourseWithCourseID(courseID: Int, completionBlock: (courseData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(courseData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(courseData: parsedData)
            } catch {
                completionBlock(courseData: nil)
            }
        }
        
        APIPublicRequest(coursesEndpoint.stringByAppendingPathComponent(String(courseID)), parameters: nil, callbackHandler: handlerBlock)
    }
    
    
    /** An evaluation is a component of a course in which the teacher determines the extent of the students understanding of the program. Current known implementations of evaluations are: tests, exams, projects, online tests and ad-hoc evaluations. Courses are identified with a numeric code that you need to provide. An example response can be found in http://fenixedu.org/dev/api/#toc_13
    
    :param: courseID                The ID number of the course you wish to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSArray with the parsed JSON data. Each array item contains an NSDictionary with information about each evaluation.
    */
    public func getCourseEvaluationsWithCourseID(courseID: Int, completionBlock: (courseEvalData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(courseEvalData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(courseEvalData: parsedData)
            } catch {
                completionBlock(courseEvalData: nil)
            }
        }
        
        APIPublicRequest(coursesEndpoint.stringByAppendingPathComponent(String(courseID)).stringByAppendingPathComponent(evaluationsEndpoint), parameters: nil, callbackHandler: handlerBlock)
    }
    
    
    
    /** Groups are used in courses for a wide range of purposes. The most typical are for creating teams of students for laboratories or projects. Some groups are shared among different courses. The enrolment of student groups may be atomic or individual, and may be restricted to an enrolment period. Courses are identified with a numeric code that you need to provide. An example response can be found in http://fenixedu.org/dev/api/#toc_16
    
    :param: courseID                The ID number of the course you wish to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getCourseGroupsWithCourseID(courseID: Int, completionBlock: (courseGroupData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(courseGroupData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(courseGroupData: parsedData)
            } catch {
                completionBlock(courseGroupData: nil)
            }
        }
        
        APIPublicRequest(coursesEndpoint.stringByAppendingPathComponent(String(courseID)).stringByAppendingPathComponent(groupsEndpoint), parameters: nil, callbackHandler: handlerBlock)
    }
    
    
    /** This endpoint lists all the students attending the specified course. For each student it indicates the corresponding degree. The endpoint also returns the number of students officially enroled in the course. Courses are identified with a numeric code that you need to provide. An example response can be found in http://fenixedu.org/dev/api/#toc_22
    
    :param: courseID                The ID number of the course you wish to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getCourseStudentsWithCourseID(courseID: Int, completionBlock: (courseGroupData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(courseGroupData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(courseGroupData: parsedData)
            } catch {
                completionBlock(courseGroupData: nil)
            }
        }
        
        APIPublicRequest(coursesEndpoint.stringByAppendingPathComponent(String(courseID)).stringByAppendingPathComponent(studentsEndpoint), parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the information for all degrees. If no academicTerm is defined it returns the degree information for the current Academic Term. An example response can be found in http://fenixedu.org/dev/api/#toc_25
    
    :param: academicTerm            The academic term of witch you want to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getDegreesWithAcademicTerm(academicTerm : String?, completionBlock: (degreeData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(degreeData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(degreeData: parsedData)
            } catch {
                completionBlock(degreeData: nil)
            }
        }
        
        // Setup parameters
        var requestParameters : [String:String]? = nil
        if academicTerm != nil{
            requestParameters = ["academicTerm" : academicTerm!]
        }
        
        APIPublicRequest(degreesEndpoint, parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the information for all degrees. If no academicTerm is defined it returns the degree information for the current Academic Term. An example response can be found in http://fenixedu.org/dev/api/#toc_25
    
    :param: academicTerm            The academic term of witch you want to get information about
    :param: degreeID                The ID number of the degree you want to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getDegreesWithAcademicTermAndDegreeID(academicTerm : String?, degreeID : Int, completionBlock: (degreeData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(degreeData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(degreeData: parsedData)
            } catch {
                completionBlock(degreeData: nil)
            }
        }
        
        // Setup parameters
        var requestParameters : [String:String]? = nil
        if academicTerm != nil{
            requestParameters = ["academicTerm" : academicTerm!]
        }
        
        APIPublicRequest(degreesEndpoint.stringByAppendingPathComponent(String(degreeID)), parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the informations for a degree's courses. If no academicTerm is defined it returns the degree information for the currentAcademicTerm. Each degree is identified by a degreeID which you must provide. An example response can be found in http://fenixedu.org/dev/api/#toc_33
    
    :param: academicTerm            The academic term of witch you want to get information about
    :param: degreeID                The ID number of the degree you want to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getDegreeCoursesWithDegreeID(academicTerm : String?, degreeID : Int, completionBlock: (degreeData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(degreeData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(degreeData: parsedData)
            } catch {
                completionBlock(degreeData: nil)
            }
        }
        
        // Setup parameters
        var requestParameters : [String:String]? = nil
        if academicTerm != nil{
            requestParameters = ["academicTerm" : academicTerm!]
        }
        
        APIPublicRequest(degreesEndpoint.stringByAppendingPathComponent(String(degreeID)).stringByAppendingPathComponent(coursesEndpoint), parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    
    /** This endpoint returns information about the space for a given spaceID, as well as its contained and parent spaces. The spaceID can be for any of these types: "CAMPUS", "BUILDING", "FLOOR" or "ROOM". If no spaceID is provided, a list of campii is returned. An example response can be found in http://fenixedu.org/dev/api/#toc_68
    
    :param: spaceID                 The ID number of the space you want to get information about
    :param: day                     To get specific day information you can specify the day about which you want to query the API. This needs to be in the dd/mm/yyyy format
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getSpaceWithSpaceID(spaceID : String?, day : String?, completionBlock: (spaceData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(spaceData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(spaceData: parsedData)
            } catch {
                completionBlock(spaceData: nil)
            }
        }
        
        // Setup parameters
        var requestParameters : [String:String]? = nil
        if day != nil{
            requestParameters = ["day" : day!]
        }
        let endpoint = spacesEndpoint.stringByAppendingPathComponent(String(spaceID ?? ""))
        
        APIPublicRequest(endpoint, parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the space's blueprint in the required format. An example response can be found in http://fenixedu.org/dev/api/#toc_68
    
    :param: spaceID                 The ID number of the space you want to get information about
    :param: format                  The image format you want to receive. Currently the supported options are "jpeg" or "dwg".
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getSpaceBlueprintWithSpaceID(spaceID : String, format : String?, completionBlock: (spaceData: NSData?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(spaceData: nil)
                return;
            }
            completionBlock(spaceData: data)
        }
        
        // Setup parameters
        var requestParameters : [String:String]? = nil
        if format != nil{
            requestParameters = ["format" : format!]
        }
        
        APIPublicRequest(spacesEndpoint.stringByAppendingPathComponent(spaceID).stringByAppendingPathComponent("blueprint"), parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the shuttle's information. An example response can be found in http://fenixedu.org/dev/api/#get-/parking
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getShuttle(completionBlock: (shuttleData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(shuttleData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(shuttleData: parsedData)
            } catch {
                completionBlock(shuttleData: nil)
            }
            
        }
        
        APIPublicRequest(shuttleEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the car parks' information. An example response can be found in http://fenixedu.org/dev/api/#get-/shuttle
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getParking(completionBlock: (parkingData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(parkingData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(parkingData: parsedData)
            } catch {
                completionBlock(parkingData: nil)
            }
        }
        
        APIPublicRequest(carParkEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    
    
    
    
    
    
    // MARK: Private Endpoints
    
    
    /** This endpoint allows to access the current person information. An example response can be found in http://fenixedu.org/dev/api/#toc_37
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPerson(completionBlock: (personData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        APIPrivateRequest(personEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the user's class information. This information can be retrieved both in iCalendar and JSON formats. An example response can be found in http://fenixedu.org/dev/api/#toc_40
    
    :param: format                  The format of the calendar info to be returned. Currently available options are "calendar" or "json".
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonClassesCalendarWithFormat(format: String? = "json", completionBlock: (personData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        // Setup parameters
        let requestParameters = ["format" : format!]
        
        APIPrivateRequest(personEndpoint + "/" + calendarEndpoint + "/" + classesEndpoint, parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the students's evaluations information. This information can be retrieved both in iCalendar and JSON formats. An example response can be found in http://fenixedu.org/dev/api/#toc_44
    
    :param: format                  The format of the calendar info to be returned. Currently available options are "calendar" or "json".
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonEvaluationsCalendarWithFormat(format: String? = "json", completionBlock: (personData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        // Setup parameters
        let requestParameters = ["format" : format!]
        
        APIPrivateRequest(personEndpoint + "/" + calendarEndpoint + "/" + evaluationsEndpoint, parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint allows to access the student's complete curriculum. Thereby it is only available for students. An example response can be found in http://fenixedu.org/dev/api/#toc_52
    
    :param: format                  The format of the calendar info to be returned. Currently available options are "calendar" or "json".
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonCurriculum(completionBlock: (personData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        APIPrivateRequest(personEndpoint + "/" + curriculumEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the user's course information. If no academicTerm is defined it returns the degree information for the current Academic Term. An example response can be found in http://fenixedu.org/dev/api/#toc_48
    
    :param: academicTerm            The academic term of which you want to get information about
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonCoursesWithAcademicTerm(academicTerm: String?, completionBlock: (personData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        // Setup parameters
        var requestParameters : [String:String]? = nil
        if academicTerm != nil{
            requestParameters = ["academicTerm" : academicTerm!]
        }
        
        APIPrivateRequest(personEndpoint + "/" + coursesEndpoint, parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the student's written evaluation information. An example response can be found in http://fenixedu.org/dev/api/#toc_55
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonEvaluations(completionBlock: (personData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        APIPrivateRequest(personEndpoint + "/" + evaluationsEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** This endpoint returns the student's written evaluation information for a single evaluation. You need to provide the evaluation ID of the resource you are trying to access. An example response can be found in http://fenixedu.org/dev/api/#toc_55
    
    :param: evaluationID            The evaluation ID of the item you want to query the API for.
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonEvaluationsWithEvaluationID(evaluationID : String, completionBlock: (personData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        APIPrivateRequest(personEndpoint + "/" + evaluationsEndpoint + "/" + String(evaluationID), parameters: nil, callbackHandler: handlerBlock)
    }
    
    /** This endpoint allows the student to enroll or disenroll from a written evaluation. You need to provide the evaluation ID of the resource you are trying to access. An example response can be found in http://fenixedu.org/dev/api/#toc_58
    
    :param: evaluationID            The evaluation ID of the item you want to query the API for.
    :param: shouldEnrol             A boolean to set the enrolment status for the evaluation item with the specified ID.
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func enrolInEvaluationWithEvaluationID(evaluationID : String, shouldEnrol: Bool, completionBlock: (personData: NSArray?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSArray
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        // Setup parameters
        let requestParameters = ["enrol" : (shouldEnrol ? "yes" : "no")]
        
        APIPrivateRequest(personEndpoint + "/" + evaluationsEndpoint + "/" + String(evaluationID), parameters: requestParameters, callbackHandler: handlerBlock)
    }
    
    /**  This endpoint returns user's payments information. An example response can be found in http://fenixedu.org/dev/api/#toc_58
    
    :param: completionBlock         The closure to be executed when the network request completes
    
    :returns: Returns an NSDictionary with the parsed JSON data.
    */
    public func getPersonPayments(completionBlock: (personData: NSDictionary?)->()) {
        
        let handlerBlock : APIResponseBlock = {APIResponseBlock in
            
            guard let data = APIResponseBlock.data else {
                completionBlock(personData: nil)
                return;
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableLeaves) as? NSDictionary
                completionBlock(personData: parsedData)
            } catch {
                completionBlock(personData: nil)
            }
        }
        
        APIPrivateRequest(personEndpoint + "/" + paymentsEndpoint, parameters: nil, callbackHandler: handlerBlock)
    }
    
    
    
    
    
    // MARK: NSURLSession Delegate Protocol
    
    public func URLSession(session: NSURLSession,
        task: NSURLSessionTask,
        didCompleteWithError error: NSError?){
        print("Did end task with error \(error)")
            if(error != nil){
                let reqHttpResponse = task.response as! NSHTTPURLResponse
                let taskKey = task as? NSURLSessionDownloadTask
                
                if let APIResponseBlock = self.responseHandlers[taskKey!.taskIdentifier] {
                    APIResponseBlock(data: NSData(), httpResponse: reqHttpResponse)
                }
            }
    }
    
    func URLSession( session: NSURLSession,
         downloadTask: NSURLSessionDownloadTask,
        didFinishDownloadingToURL location: NSURL){
         print("Calling response handler...")
        
        guard let reqData = NSData(contentsOfURL: location),
              let reqHttpResponse = downloadTask.response as? NSHTTPURLResponse,
              let APIResponseBlock = self.responseHandlers[downloadTask.taskIdentifier] else {
                print("A response block was not found for.... some... thing. meh.. whatever...")
                return;
            }
        
        APIResponseBlock(data: reqData, httpResponse: reqHttpResponse)
    }
}






// MARK: Helper Methods
func percentEscape(str : String) -> String {
    let escapedString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, str, " ", ":/?@!$&'()*+,;=",kCFStringEncodingASCII)
    let nsTypeString = escapedString as NSString
    let swiftString:String = nsTypeString as String
    return swiftString.stringByReplacingOccurrencesOfString(" ", withString: "+", options: NSStringCompareOptions.LiteralSearch)
}
