//
//  FenixEdu_iOS_SDK.swift
//  
//
//  Created by Paulo Branco on 14/06/15.
//
//

import UIKit
import Foundation

protocol FenixEdu_iOS_SDKDelegate {
    func didDownloadPerson(requestData :NSData, requestStatus :NSHTTPURLResponse) -> ()
}

class FenixEdu_iOS_SDK: NSObject, NSURLSessionTaskDelegate {
    
    private var clientID, clientSecret, redirectURL, lang : String
    private let APIBaseURL = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1"
    private var backgroundURLSession : NSURLSession
    private var delegateQueue = NSOperationQueue()
    var delegate : FenixEdu_iOS_SDKDelegate?
    var responseHandlers = Dictionary<NSURLSessionDownloadTask, (String, Int) -> String>()
    
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
    
    
    func makeParamterStringFromDictionary(parameters :[String:String]) -> String{
        var parameterString = String()
        var parameter, key : String
        for (parameter, key) in parameters {
            if !parameterString.isEmpty {
                parameterString = parameter + "&"
            } else {
                parameterString += parameter + "=" + key
            }
        }
        return "?" + parameterString
    }
    
    
    func testResquest(){
        var request : NSURLRequest = NSURLRequest(URL: NSURL(string: "http://google.com")!)
        var task : NSURLSessionDownloadTask = self.backgroundURLSession.downloadTaskWithRequest(request)
        self.responseHandlers[task] = testResponseHandler
        task.resume()
        
    }
    
    func testResponseHandler(testString :String, testInt :Int) -> String{
        println("Response handler retrieved and called!")
        return "Macarena!"
    }
    
    
    func URLSession(session: NSURLSession,
        task: NSURLSessionTask,
        didCompleteWithError error: NSError?){
        
        println("Did end something...")
            
    }
    
    func URLSession( session: NSURLSession,
         downloadTask: NSURLSessionDownloadTask,
        didFinishDownloadingToURL location: NSURL){
         println("Calling response handler...")
        self.responseHandlers[downloadTask]!("1",1)
    }
}
