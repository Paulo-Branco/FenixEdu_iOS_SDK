# FenixEdu_iOS_API


 * 

### Getting started:

To initialize an instance of the API just use the designated initializer passing in your client ID, client secret and redirect URL.

```objective-c
var myFenixEduInstance = FenixEdu_iOS_SDK(clientID: "CLIENT_ID", clientSecret: "CLIENT_SECRET", redirectURL: "REDIRECT_URL")
```

To perform private requests you'll need an access token which can be retrieved with the user's refresh token. To set it, just set the refreshToken property with the correct value:

```objective-c
myFenixEduInstance.refreshToken = "USER'S REFRESH TOKEN"
```

The framework manages the user's access token so you shouldn't have to manually refresh it. It is automatically refreshed whenever a new refresh token is set and at the start of every request, if the previous access token has expired.

### Making requests:

This API leverages the lastest URLSession frameworks to provide you with safe methods that can be called in every ocasion, even if your app is running in the background. Because of this, all of the requests are performed asyncronously with callbacks being used to process the data returned by FenixEdu's API Services.

As an example, if you wish to retrieve canteen information for the next week, simply add the following code:

```objective-c
myFenixInstance.getCanteen { (canteenData) -> () in 
// Perform data validation, parsing and persistence 

// This code will be executed when the URL request ends.
}
```


### More info:

 * [FenixEdu](https://fenixedu.org/) for the official API documentation.