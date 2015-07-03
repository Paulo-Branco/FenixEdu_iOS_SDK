# FenixEdu_iOS_API

A Swift Library to access FenixEdu's API services. Still in a very early stage,  it aims to provide iOS developers with a quick and safe way to consume FenixEdu's REST API and develop amazing apps. 

### Getting started:

To initialize an instance of the API just use the designated initializer passing in your client ID, client secret and redirect URL.

```swift
var myFenixEduInstance = FenixEdu_iOS_SDK(clientID: "CLIENT_ID", clientSecret: "CLIENT_SECRET", redirectURL: "REDIRECT_URL")
```

To perform private requests you'll need an access token which can be retrieved with the user's refresh token. To set it, just set the refreshToken property with the correct value:

```swift
myFenixEduInstance.refreshToken = "USER'S REFRESH TOKEN"
```

The framework manages the user's access token so you shouldn't have to manually refresh it. It is automatically refreshed whenever a new refresh token is set and at the start of every request, if the previous access token has expired.

### Making requests:

This API leverages the lastest URLSession frameworks to provide you with safe methods that can be called in every ocasion, even if your app is running in the background. Because of this, all of the requests are performed asyncronously with callbacks being used to process the data returned by FenixEdu's API Services.

As an example, if you wish to retrieve canteen information for the next week, simply add the following code:

```swift
myFenixInstance.getCanteen { (canteenData) -> () in 
// Perform data validation, parsing and persistence 

// This code will be executed when the URL request ends.
}
```

### To-Do:

 * ~~Public Endpoints~~
 * ~~Private Endpoints~~
 * Code -> Access token exchange (scheduled for 0.9).
 * Unit Testing (scheduled for 1.0).
 
### Version History:

#### 0.8:
Public and Private endpoints.


### More info:

 * [FenixEdu](https://fenixedu.org/) for the official API documentation.